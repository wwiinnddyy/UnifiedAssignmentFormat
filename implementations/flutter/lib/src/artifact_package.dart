import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'artifact_manifest.dart';
import 'constants.dart';
import 'csv.dart';
import 'errors.dart';
import 'html.dart';
import 'model.dart';
import 'pdf.dart';

/// Resource limits applied while reading an untrusted UAF artifact package.
///
/// The defaults are intentionally generous for normal school documents while
/// bounding ZIP bombs and unexpectedly large synchronous allocations on
/// Flutter clients. Callers handling a trusted archive with larger supporting
/// artifacts may pass a custom instance to the read APIs.
final class UafPackageReadLimits {
  /// Creates package read limits.
  const UafPackageReadLimits({
    this.maxZipBytes = 64 * 1024 * 1024,
    this.maxManifestBytes = 1024 * 1024,
    this.maxEntries = 128,
    this.maxEntryBytes = 64 * 1024 * 1024,
    this.maxTotalUncompressedBytes = 128 * 1024 * 1024,
    this.maxCompressionRatio = 1000,
    this.maxPathDepth = 16,
  }) : assert(maxZipBytes > 0),
       assert(maxManifestBytes > 0),
       assert(maxEntries >= 4),
       assert(maxEntryBytes > 0),
       assert(maxTotalUncompressedBytes >= maxEntryBytes),
       assert(maxCompressionRatio > 0),
       assert(maxPathDepth > 0);

  /// Maximum compressed `.uaf.zip` input size.
  final int maxZipBytes;

  /// Maximum uncompressed `uaf-manifest.json` size.
  final int maxManifestBytes;

  /// Maximum number of ZIP or directory files, including the manifest.
  final int maxEntries;

  /// Maximum uncompressed size of one manifest or artifact.
  final int maxEntryBytes;

  /// Maximum aggregate uncompressed size of all package files.
  final int maxTotalUncompressedBytes;

  /// Maximum declared uncompressed-to-compressed ratio for one ZIP entry.
  final int maxCompressionRatio;

  /// Maximum number of `/`-separated path segments.
  final int maxPathDepth;
}

/// A verified UAF artifact set held entirely in memory.
///
/// Instances created by the public factories have already passed manifest,
/// path, byte-length, SHA-256, and CSV/HTML/PDF payload checks. Byte arrays are
/// defensively copied on input and output.
final class UafArtifactPackage {
  UafArtifactPackage._(
    this.manifest,
    this.payload,
    Map<String, Uint8List> artifacts,
  ) : _artifacts = Map<String, Uint8List>.unmodifiable(
        artifacts.map(
          (String path, Uint8List bytes) =>
              MapEntry<String, Uint8List>(path, _copyBytes(bytes)),
        ),
      );

  /// Decodes and verifies a `.uaf.zip` archive held in memory.
  factory UafArtifactPackage.fromBytes(
    List<int> bytes, {
    UafPackageReadLimits limits = const UafPackageReadLimits(),
  }) {
    if (bytes.length > limits.maxZipBytes) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'UAF ZIP exceeds the ${limits.maxZipBytes}-byte input limit.',
      );
    }
    _validateZipEnvelope(bytes, limits);
    // Parse metadata without ZipDecoder: it may inflate Unix symlink entries
    // while constructing ArchiveFile objects, before callers can apply limits.
    late final ZipDirectory directory;
    try {
      directory = ZipDirectory()..read(InputMemoryStream(bytes));
    } catch (error, stackTrace) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'UAF ZIP package is invalid.',
        error,
        stackTrace,
      );
    }

    if (directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.totalCentralDirectoryEntriesOnThisDisk !=
            directory.totalCentralDirectoryEntries ||
        directory.totalCentralDirectoryEntries !=
            directory.fileHeaders.length) {
      throw const UafException(
        UafErrorCode.invalidPackage,
        'Multi-disk ZIP packages are not supported.',
      );
    }
    if (directory.fileHeaders.length > limits.maxEntries) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP package contains more than ${limits.maxEntries} entries.',
      );
    }

    final headerNames = <String>{};
    final files = <String, ZipFileHeader>{};
    var declaredTotalBytes = 0;
    for (final header in directory.fileHeaders) {
      final localName = header.file?.filename;
      if (localName == null || header.filename != localName) {
        throw const UafException(
          UafErrorCode.invalidPackage,
          'ZIP entry has inconsistent local and central-directory names.',
        );
      }
      final path = localName.endsWith('/')
          ? localName.substring(0, localName.length - 1)
          : localName;
      if (path.isNotEmpty) {
        _ensureSafeRelativePath(path, limits: limits);
      }
      if (!headerNames.add(localName)) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'ZIP package contains a duplicate entry: $localName',
        );
      }
      _validateZipHeader(header, bytes, limits);
      declaredTotalBytes += header.uncompressedSize;
      if (declaredTotalBytes > limits.maxTotalUncompressedBytes) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'ZIP package exceeds the ${limits.maxTotalUncompressedBytes}-byte '
          'uncompressed limit.',
        );
      }
      if (!localName.endsWith('/')) {
        files[localName] = header;
      }
    }

    _validatePortableFileSet(<String>{
      UafConstants.manifestFileName,
      ...files.keys,
    });

    final manifestHeader = files[UafConstants.manifestFileName];
    if (manifestHeader == null) {
      throw const UafException(
        UafErrorCode.invalidPackage,
        'ZIP package is missing uaf-manifest.json.',
      );
    }
    if (manifestHeader.uncompressedSize > limits.maxManifestBytes) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Manifest exceeds the ${limits.maxManifestBytes}-byte limit.',
      );
    }
    var actualTotalBytes = 0;
    Uint8List decodeEntry(ZipFileHeader header) {
      final entryBytes = _decodeZipEntry(
        header,
        bytes,
        limits: limits,
        remainingTotalBytes:
            limits.maxTotalUncompressedBytes - actualTotalBytes,
      );
      actualTotalBytes += entryBytes.length;
      return entryBytes;
    }

    final manifest = _readManifest(decodeEntry(manifestHeader));
    manifest.validate();
    _validatePackageFileSet(files.keys, manifest, sourceName: 'ZIP package');

    final artifacts = <String, Uint8List>{};
    for (final artifact in manifest.artifacts) {
      final header = files[artifact.path];
      if (header == null) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'ZIP package is missing artifact: ${artifact.path}',
        );
      }
      final artifactBytes = decodeEntry(header);
      _assertArtifactIntegrity(artifact, artifactBytes);
      artifacts[artifact.path] = artifactBytes;
    }

    return _fromVerifiedArtifacts(manifest, artifacts);
  }

  /// Decodes and verifies ZIP bytes on a worker isolate.
  static Future<UafArtifactPackage> fromBytesAsync(
    List<int> bytes, {
    UafPackageReadLimits limits = const UafPackageReadLimits(),
  }) {
    if (bytes.length > limits.maxZipBytes) {
      return Future<UafArtifactPackage>.error(
        UafException(
          UafErrorCode.invalidPackage,
          'UAF ZIP exceeds the ${limits.maxZipBytes}-byte input limit.',
        ),
      );
    }
    final copiedBytes = Uint8List.fromList(bytes);
    return Isolate.run(
      () => UafArtifactPackage.fromBytes(copiedBytes, limits: limits),
    );
  }

  /// The parsed, immutable package manifest.
  final UafArtifactManifest manifest;

  /// The canonical payload parsed from `uaf_payload.csv`.
  final UafDocument payload;

  final Map<String, Uint8List> _artifacts;

  /// All loaded artifacts as a new unmodifiable map of copied byte arrays.
  Map<String, Uint8List> get artifacts => Map<String, Uint8List>.unmodifiable(
    _artifacts.map(
      (String path, Uint8List bytes) =>
          MapEntry<String, Uint8List>(path, _copyBytes(bytes)),
    ),
  );

  /// The canonical CSV entry point decoded as strict UTF-8.
  String get csv => UafCsv.decodeUtf8(
    _requiredArtifact(_artifacts, manifest.entrypoints.payload),
  );

  /// The display HTML entry point decoded as strict UTF-8.
  String get html => _decodeUtf8(
    _requiredArtifact(_artifacts, manifest.entrypoints.display),
    manifest.entrypoints.display,
  );

  /// A defensive copy of the exchange PDF bytes.
  Uint8List get pdfBytes => getArtifact(manifest.entrypoints.exchange);

  /// Creates a complete artifact set from one validated UAF document.
  static UafArtifactPackage create(
    UafDocument payload, {
    DateTime? createdAt,
    UafPipelineInfo pipeline = const UafPipelineInfo(),
  }) {
    final artifacts = <String, Uint8List>{
      UafConstants.payloadFileName: UafCsv.serializeToUtf8(payload),
      UafConstants.displayFileName: Uint8List.fromList(
        utf8.encode(UafHtml.render(payload)),
      ),
      UafConstants.exchangePdfFileName: UafPdf.create(payload),
    };

    final manifest = _buildManifest(
      artifacts,
      (createdAt ?? DateTime.now().toUtc()).toUtc(),
      pipeline,
    );
    manifest.validate();
    return UafArtifactPackage._(manifest, payload, artifacts);
  }

  /// Parses and fully validates a manifest without reading its artifacts.
  static UafArtifactManifest parseManifest(String source) {
    return UafArtifactManifest.parseValidated(source);
  }

  /// Fully validates an already decoded manifest.
  static void validateManifest(UafArtifactManifest manifest) {
    manifest.validate();
  }

  /// Reads either a `.uaf` directory or a `.uaf.zip` file.
  static UafArtifactPackage read(
    String path, {
    UafPackageReadLimits limits = const UafPackageReadLimits(),
  }) {
    _requireNonEmptyPath(path);
    if (Directory(path).existsSync()) {
      return readDirectory(path, limits: limits);
    }
    if (File(path).existsSync()) return readZip(path, limits: limits);
    throw UafException(
      UafErrorCode.invalidPackage,
      'UAF package path not found: $path',
    );
  }

  /// Reads and verifies a directory or ZIP package on a worker isolate.
  static Future<UafArtifactPackage> readAsync(
    String path, {
    UafPackageReadLimits limits = const UafPackageReadLimits(),
  }) {
    return Isolate.run(() => read(path, limits: limits));
  }

  /// Reads and verifies a directory-form UAF package.
  static UafArtifactPackage readDirectory(
    String directoryPath, {
    UafPackageReadLimits limits = const UafPackageReadLimits(),
  }) {
    _requireNonEmptyPath(directoryPath);
    final directory = Directory(p.normalize(p.absolute(directoryPath)));
    if (!directory.existsSync()) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'UAF package directory not found: $directoryPath',
      );
    }

    final manifestPath = p.join(directory.path, UafConstants.manifestFileName);
    if (FileSystemEntity.typeSync(manifestPath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const UafException(
        UafErrorCode.invalidPackage,
        'Package is missing uaf-manifest.json or it is not a regular file.',
      );
    }

    final manifestLimit = limits.maxManifestBytes < limits.maxEntryBytes
        ? limits.maxManifestBytes
        : limits.maxEntryBytes;
    final manifestBytes = _readFileBytes(
      manifestPath,
      UafConstants.manifestFileName,
      maxBytes: manifestLimit,
    );
    final manifest = _readManifest(manifestBytes);
    manifest.validate();
    if (manifest.artifacts.length + 1 > limits.maxEntries) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Package contains more than ${limits.maxEntries} files.',
      );
    }
    final packageFiles = _directoryFileSet(directory, limits: limits);
    _validatePackageFileSet(
      packageFiles,
      manifest,
      sourceName: 'Package directory',
    );

    final canonicalRoot = directory.resolveSymbolicLinksSync();
    final artifacts = <String, Uint8List>{};
    var totalBytes = manifestBytes.length;
    if (totalBytes > limits.maxTotalUncompressedBytes) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Package exceeds the ${limits.maxTotalUncompressedBytes}-byte '
        'uncompressed limit.',
      );
    }
    for (final artifact in manifest.artifacts) {
      final artifactPath = _resolvePackagePath(directory.path, artifact.path);
      if (FileSystemEntity.typeSync(artifactPath, followLinks: false) !=
          FileSystemEntityType.file) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package is missing artifact or it is not a regular file: '
          '${artifact.path}',
        );
      }
      _ensureResolvedPathWithinRoot(
        canonicalRoot,
        File(artifactPath).resolveSymbolicLinksSync(),
        artifact.path,
      );
      if (artifact.bytes > limits.maxEntryBytes) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Artifact ${artifact.path} exceeds the '
          '${limits.maxEntryBytes}-byte limit.',
        );
      }
      totalBytes += artifact.bytes;
      if (totalBytes > limits.maxTotalUncompressedBytes) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package exceeds the ${limits.maxTotalUncompressedBytes}-byte '
          'uncompressed limit.',
        );
      }
      final bytes = _readFileBytes(
        artifactPath,
        artifact.path,
        maxBytes: limits.maxEntryBytes,
      );
      _assertArtifactIntegrity(artifact, bytes);
      artifacts[artifact.path] = bytes;
    }

    return _fromVerifiedArtifacts(manifest, artifacts);
  }

  /// Reads and verifies a ZIP-form UAF package.
  static UafArtifactPackage readZip(
    String zipPath, {
    UafPackageReadLimits limits = const UafPackageReadLimits(),
  }) {
    _requireNonEmptyPath(zipPath);
    if (!File(zipPath).existsSync()) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'UAF ZIP package not found: $zipPath',
      );
    }
    return UafArtifactPackage.fromBytes(
      _readFileBytes(zipPath, zipPath, maxBytes: limits.maxZipBytes),
      limits: limits,
    );
  }

  /// Returns a defensive copy of one loaded artifact.
  Uint8List getArtifact(String relativePath) {
    _ensureSafeRelativePath(relativePath);
    return _copyBytes(_requiredArtifact(_artifacts, relativePath));
  }

  /// Serializes this package as a ZIP archive in memory.
  Uint8List toZipBytes() {
    final archive = Archive();
    final manifestBytes = _manifestBytes(manifest);
    archive.addFile(
      ArchiveFile(
        UafConstants.manifestFileName,
        manifestBytes.length,
        manifestBytes,
      ),
    );
    for (final artifact in manifest.artifacts) {
      final bytes = _requiredArtifact(_artifacts, artifact.path);
      archive.addFile(ArchiveFile(artifact.path, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  /// Writes a clean directory-form package, with the manifest written last.
  void writeDirectory(String directoryPath, {bool overwrite = false}) {
    _requireNonEmptyPath(directoryPath);
    final root = p.normalize(p.absolute(directoryPath));
    final directory = Directory(root);
    final targetType = FileSystemEntity.typeSync(root, followLinks: false);
    if (targetType == FileSystemEntityType.directory) {
      final hasEntries = directory.listSync(followLinks: false).isNotEmpty;
      if (!overwrite && hasEntries) {
        throw FileSystemException(
          'Directory already exists and is not empty.',
          root,
        );
      }
    } else if (targetType != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Package destination exists and is not a directory.',
        root,
      );
    }

    final temporaryRoot = _uniqueSiblingPath(root, 'tmp');
    final temporaryDirectory = Directory(temporaryRoot);
    try {
      _writeDirectoryContents(temporaryRoot, manifest, _artifacts);
      _commitDirectory(
        temporaryDirectory,
        directory,
        targetExists: targetType == FileSystemEntityType.directory,
      );
    } catch (_) {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  /// Writes a ZIP-form package.
  void writeZip(String zipPath, {bool overwrite = false}) {
    _requireNonEmptyPath(zipPath);
    final fullPath = p.normalize(p.absolute(zipPath));
    final type = FileSystemEntity.typeSync(fullPath, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (!overwrite) {
        throw FileSystemException('ZIP file already exists.', fullPath);
      }
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'ZIP destination is not a regular file.',
          fullPath,
        );
      }
    }

    final parent = p.dirname(fullPath);
    Directory(parent).createSync(recursive: true);
    final temporaryPath = _uniqueSiblingPath(fullPath, 'tmp');
    final temporaryFile = File(temporaryPath);
    try {
      temporaryFile.writeAsBytesSync(toZipBytes(), flush: true);
      _commitFile(
        temporaryFile,
        File(fullPath),
        targetExists: type == FileSystemEntityType.file,
      );
    } catch (_) {
      if (temporaryFile.existsSync()) temporaryFile.deleteSync();
      rethrow;
    }
  }

  static UafArtifactPackage _fromVerifiedArtifacts(
    UafArtifactManifest manifest,
    Map<String, Uint8List> artifacts,
  ) {
    final csvPayload = UafCsv.parseUtf8(
      _requiredArtifact(artifacts, manifest.entrypoints.payload),
    );
    final htmlPayload = UafHtml.validateOrThrow(
      _decodeUtf8(
        _requiredArtifact(artifacts, manifest.entrypoints.display),
        manifest.entrypoints.display,
      ),
    );
    _ensureSamePayload('HTML', csvPayload, htmlPayload);

    final pdfPayload = UafPdf.extractPayload(
      _requiredArtifact(artifacts, manifest.entrypoints.exchange),
    );
    _ensureSamePayload('PDF', csvPayload, pdfPayload);
    return UafArtifactPackage._(manifest, csvPayload, artifacts);
  }
}

void _writeDirectoryContents(
  String root,
  UafArtifactManifest manifest,
  Map<String, Uint8List> artifacts,
) {
  Directory(root).createSync(recursive: true);
  for (final artifact in manifest.artifacts) {
    final artifactPath = _resolvePackagePath(root, artifact.path);
    Directory(p.dirname(artifactPath)).createSync(recursive: true);
    File(artifactPath).writeAsBytesSync(
      _requiredArtifact(artifacts, artifact.path),
      flush: true,
    );
  }
  File(
    p.join(root, UafConstants.manifestFileName),
  ).writeAsBytesSync(_manifestBytes(manifest), flush: true);
}

void _commitDirectory(
  Directory temporary,
  Directory target, {
  required bool targetExists,
}) {
  if (!targetExists) {
    temporary.renameSync(target.path);
    return;
  }

  final backup = Directory(_uniqueSiblingPath(target.path, 'backup'));
  target.renameSync(backup.path);
  try {
    temporary.renameSync(target.path);
  } catch (_) {
    if (!target.existsSync() && backup.existsSync()) {
      backup.renameSync(target.path);
    }
    rethrow;
  }
  backup.deleteSync(recursive: true);
}

void _commitFile(File temporary, File target, {required bool targetExists}) {
  if (!targetExists) {
    temporary.renameSync(target.path);
    return;
  }

  final backup = File(_uniqueSiblingPath(target.path, 'backup'));
  target.renameSync(backup.path);
  try {
    temporary.renameSync(target.path);
  } catch (_) {
    if (!target.existsSync() && backup.existsSync()) {
      backup.renameSync(target.path);
    }
    rethrow;
  }
  backup.deleteSync();
}

String _uniqueSiblingPath(String targetPath, String purpose) {
  final parent = p.dirname(targetPath);
  final base = p.basename(targetPath);
  for (var attempt = 0; attempt < 100; attempt++) {
    final nonce = DateTime.now().microsecondsSinceEpoch + attempt;
    final candidate = p.join(parent, '.$base.uaf-$purpose-$pid-$nonce');
    if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return candidate;
    }
  }
  throw FileSystemException(
    'Unable to allocate a temporary package path.',
    targetPath,
  );
}

UafArtifactManifest _buildManifest(
  Map<String, Uint8List> artifacts,
  DateTime createdAt,
  UafPipelineInfo pipeline,
) {
  UafArtifactEntry createEntry(String role, String path, String mediaType) {
    final bytes = artifacts[path]!;
    return UafArtifactEntry(
      role: role,
      path: path,
      mediaType: mediaType,
      bytes: bytes.length,
      sha256: _sha256(bytes),
    );
  }

  return UafArtifactManifest(
    createdAt: createdAt,
    entrypoints: const UafPackageEntrypoints(),
    artifacts: <UafArtifactEntry>[
      createEntry(
        'payload.csv',
        UafConstants.payloadFileName,
        'text/csv; charset=utf-8',
      ),
      createEntry(
        'display.html',
        UafConstants.displayFileName,
        'text/html; charset=utf-8',
      ),
      createEntry(
        'exchange.pdf',
        UafConstants.exchangePdfFileName,
        'application/pdf',
      ),
    ],
    pipeline: pipeline,
  );
}

UafArtifactManifest _readManifest(Uint8List bytes) {
  try {
    return UafArtifactPackage.parseManifest(
      utf8.decode(bytes, allowMalformed: false),
    );
  } catch (error, stackTrace) {
    if (error is UafException) rethrow;
    throw UafException(
      UafErrorCode.invalidPackage,
      'Manifest JSON is invalid.',
      error,
      stackTrace,
    );
  }
}

void _assertArtifactIntegrity(UafArtifactEntry artifact, Uint8List bytes) {
  if (artifact.bytes != bytes.length) {
    throw UafException(
      UafErrorCode.hashMismatch,
      'Artifact ${artifact.path} byte size mismatch: expected '
      '${artifact.bytes}, got ${bytes.length}.',
    );
  }
  if (artifact.sha256 != _sha256(bytes)) {
    throw UafException(
      UafErrorCode.hashMismatch,
      'Artifact ${artifact.path} sha256 mismatch.',
    );
  }
}

void _validatePackageFileSet(
  Iterable<String> actualFiles,
  UafArtifactManifest manifest, {
  required String sourceName,
}) {
  final expected = <String>{
    UafConstants.manifestFileName,
    for (final artifact in manifest.artifacts) artifact.path,
  };
  final actual = Set<String>.of(actualFiles);
  for (final path in actual) {
    if (!expected.contains(path)) {
      throw UafException(
        UafErrorCode.invalidPackage,
        '$sourceName contains an unlisted file: $path',
      );
    }
  }
  for (final path in expected) {
    if (!actual.contains(path)) {
      throw UafException(
        UafErrorCode.invalidPackage,
        '$sourceName is missing a listed file: $path',
      );
    }
  }
}

Set<String> _directoryFileSet(
  Directory directory, {
  required UafPackageReadLimits limits,
}) {
  final files = <String>{};
  try {
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package directory must not contain symbolic links: ${entity.path}',
        );
      }
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package contains a non-regular file: ${entity.path}',
        );
      }

      final relativePath = p
          .relative(entity.path, from: directory.path)
          .replaceAll('\\', '/');
      _ensureSafeRelativePath(relativePath, limits: limits);
      if (!files.add(relativePath)) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package contains a duplicate file: $relativePath',
        );
      }
      if (files.length > limits.maxEntries) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package contains more than ${limits.maxEntries} files.',
        );
      }
    }
    _validatePortableFileSet(files);
  } on UafException {
    rethrow;
  } catch (error, stackTrace) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unable to enumerate package directory.',
      error,
      stackTrace,
    );
  }
  return files;
}

String _resolvePackagePath(String root, String relativePath) {
  _ensureSafeRelativePath(relativePath);
  final normalizedRoot = p.normalize(p.absolute(root));
  final resolved = p.normalize(
    p.joinAll(<String>[normalizedRoot, ...p.posix.split(relativePath)]),
  );
  if (!p.isWithin(normalizedRoot, resolved)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Package path escapes the package root: $relativePath',
    );
  }
  return resolved;
}

void _ensureResolvedPathWithinRoot(
  String canonicalRoot,
  String resolvedPath,
  String relativePath,
) {
  if (!p.isWithin(canonicalRoot, resolvedPath)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Package path escapes the package root: $relativePath',
    );
  }
}

void _ensureSafeRelativePath(
  String relativePath, {
  UafPackageReadLimits limits = const UafPackageReadLimits(),
}) {
  final segments = relativePath.split('/');
  if (relativePath.isEmpty ||
      relativePath.contains('\\') ||
      relativePath.contains('://') ||
      relativePath.startsWith('/') ||
      _drivePrefixPattern.hasMatch(relativePath) ||
      !_relativePathPattern.hasMatch(relativePath) ||
      segments.length > limits.maxPathDepth ||
      segments.any(
        (String segment) =>
            segment.isEmpty ||
            segment == '.' ||
            segment == '..' ||
            segment.endsWith('.') ||
            segment.endsWith(' ') ||
            _isWindowsReservedSegment(segment),
      )) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Invalid package path: $relativePath',
    );
  }
}

void _validateZipEnvelope(List<int> bytes, UafPackageReadLimits limits) {
  const signature = 0x06054b50;
  final searchStart = bytes.length > 65557 ? bytes.length - 65557 : 0;
  var offset = -1;
  for (var index = bytes.length - 22; index >= searchStart; index--) {
    if (_readUint32Le(bytes, index) == signature &&
        index + 22 <= bytes.length &&
        index + 22 + _readUint16Le(bytes, index + 20) == bytes.length) {
      offset = index;
      break;
    }
  }
  if (offset < 0 || offset + 22 > bytes.length) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'ZIP end-of-central-directory record is missing.',
    );
  }

  final disk = _readUint16Le(bytes, offset + 4);
  final centralDisk = _readUint16Le(bytes, offset + 6);
  final entriesOnDisk = _readUint16Le(bytes, offset + 8);
  final totalEntries = _readUint16Le(bytes, offset + 10);
  final centralSize = _readUint32Le(bytes, offset + 12);
  final centralOffset = _readUint32Le(bytes, offset + 16);
  final commentLength = _readUint16Le(bytes, offset + 20);
  if (offset + 22 + commentLength != bytes.length) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'ZIP contains trailing bytes or a truncated comment.',
    );
  }
  if (disk != 0 ||
      centralDisk != 0 ||
      entriesOnDisk != totalEntries ||
      totalEntries == 0xffff ||
      centralSize == 0xffffffff ||
      centralOffset == 0xffffffff) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'Multi-disk and ZIP64 packages are not supported.',
    );
  }
  if (totalEntries > limits.maxEntries) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP package contains more than ${limits.maxEntries} entries.',
    );
  }
  if (centralOffset + centralSize > offset) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'ZIP central directory is outside the archive.',
    );
  }
}

void _validateZipHeader(
  ZipFileHeader header,
  List<int> archiveBytes,
  UafPackageReadLimits limits,
) {
  const allowedMethods = <int>{0, 8};
  const forbiddenFlags = 0x0001 | 0x0020 | 0x0040 | 0x2000;

  if (header.diskNumberStart != 0) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'ZIP entries must start on disk zero.',
    );
  }
  if ((header.generalPurposeBitFlag & forbiddenFlags) != 0) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry uses encryption or unsupported flags: '
      '${header.filename}',
    );
  }
  if (!allowedMethods.contains(header.compressionMethod)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry uses an unsupported compression method: ${header.filename}',
    );
  }
  if (header.versionNeededToExtract >= 45 ||
      header.compressedSize == 0xffffffff ||
      header.uncompressedSize == 0xffffffff) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP64 entries are not supported: ${header.filename}',
    );
  }
  if (header.uncompressedSize > limits.maxEntryBytes) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry ${header.filename} exceeds the '
      '${limits.maxEntryBytes}-byte limit.',
    );
  }
  if (header.uncompressedSize > 0 && header.compressedSize == 0) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry has an impossible compressed size: ${header.filename}',
    );
  }
  if (header.compressionMethod == 0 &&
      header.compressedSize != header.uncompressedSize) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Stored ZIP entry has inconsistent compressed and uncompressed sizes: '
      '${header.filename}',
    );
  }
  if (header.compressedSize > 0 &&
      header.uncompressedSize >
          header.compressedSize * limits.maxCompressionRatio) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry ${header.filename} exceeds the allowed compression ratio.',
    );
  }

  final os = header.versionMadeBy >> 8;
  if (os == 3) {
    final unixType = (header.externalFileAttributes >> 16) & 0xf000;
    if (unixType != 0 && unixType != 0x4000 && unixType != 0x8000) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP package contains a non-regular Unix entry: ${header.filename}',
      );
    }
    if ((unixType == 0x4000) != header.filename.endsWith('/')) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP directory metadata conflicts with its path: ${header.filename}',
      );
    }
  }
  if ((header.externalFileAttributes & 0x10) != 0 &&
      !header.filename.endsWith('/')) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP directory metadata conflicts with its path: ${header.filename}',
    );
  }

  final offset = header.localHeaderOffset;
  if (offset < 0 || offset + 30 > archiveBytes.length) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP local header is outside the archive: ${header.filename}',
    );
  }
  if (_readUint32Le(archiveBytes, offset) != 0x04034b50) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry has an invalid local header: ${header.filename}',
    );
  }
  final localFlags = _readUint16Le(archiveBytes, offset + 6);
  final localMethod = _readUint16Le(archiveBytes, offset + 8);
  final localCrc = _readUint32Le(archiveBytes, offset + 14);
  final localCompressedSize = _readUint32Le(archiveBytes, offset + 18);
  final localUncompressedSize = _readUint32Le(archiveBytes, offset + 22);
  final nameLength = _readUint16Le(archiveBytes, offset + 26);
  final extraLength = _readUint16Le(archiveBytes, offset + 28);
  final nameStart = offset + 30;
  final dataStart = nameStart + nameLength + extraLength;
  if (dataStart < nameStart ||
      dataStart + header.compressedSize > archiveBytes.length) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry data is outside the archive: ${header.filename}',
    );
  }
  final localName = latin1.decode(
    archiveBytes.sublist(nameStart, nameStart + nameLength),
  );
  final usesDataDescriptor = (localFlags & 0x0008) != 0;
  final localSizesMatch = usesDataDescriptor
      ? (localCrc == 0 || localCrc == header.crc32) &&
            (localCompressedSize == 0 ||
                localCompressedSize == header.compressedSize) &&
            (localUncompressedSize == 0 ||
                localUncompressedSize == header.uncompressedSize)
      : localCrc == header.crc32 &&
            localCompressedSize == header.compressedSize &&
            localUncompressedSize == header.uncompressedSize;
  if (localName != header.filename ||
      localFlags != header.generalPurposeBitFlag ||
      localMethod != header.compressionMethod ||
      !localSizesMatch) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP local and central headers disagree: ${header.filename}',
    );
  }

  if (usesDataDescriptor) {
    var descriptorOffset = dataStart + header.compressedSize;
    if (descriptorOffset + 12 > archiveBytes.length) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP data descriptor is truncated: ${header.filename}',
      );
    }
    if (_readUint32Le(archiveBytes, descriptorOffset) == 0x08074b50) {
      descriptorOffset += 4;
    }
    if (descriptorOffset + 12 > archiveBytes.length ||
        _readUint32Le(archiveBytes, descriptorOffset) != header.crc32 ||
        _readUint32Le(archiveBytes, descriptorOffset + 4) !=
            header.compressedSize ||
        _readUint32Le(archiveBytes, descriptorOffset + 8) !=
            header.uncompressedSize) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP data descriptor disagrees with the central header: '
        '${header.filename}',
      );
    }
  }
}

int _readUint16Le(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32Le(List<int> bytes, int offset) {
  return _readUint16Le(bytes, offset) |
      (_readUint16Le(bytes, offset + 2) << 16);
}

void _validatePortableFileSet(Iterable<String> paths) {
  final byPortableKey = <String, String>{};
  final keys = <String>{};
  for (final path in paths) {
    _ensureSafeRelativePath(path);
    final key = _portablePathKey(path);
    final existing = byPortableKey[key];
    if (existing != null && existing != path) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Package paths collide on a portable file system: '
        '$existing and $path.',
      );
    }
    byPortableKey[key] = path;
    keys.add(key);
  }

  for (final entry in byPortableKey.entries) {
    final segments = entry.key.split('/');
    for (var length = 1; length < segments.length; length++) {
      final prefix = segments.take(length).join('/');
      if (keys.contains(prefix)) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Package file path is also used as a directory prefix: '
          '${byPortableKey[prefix]} and ${entry.value}.',
        );
      }
    }
  }
}

String _portablePathKey(String path) => path.toLowerCase();

bool _isWindowsReservedSegment(String segment) {
  final baseName = segment.split('.').first.toUpperCase();
  return _windowsReservedNames.contains(baseName);
}

Uint8List _decodeZipEntry(
  ZipFileHeader header,
  List<int> archiveBytes, {
  required UafPackageReadLimits limits,
  required int remainingTotalBytes,
}) {
  // ArchiveFile.content performs an unbounded full inflation. Decode the raw
  // local-entry bytes through a sink that aborts as soon as any limit is hit.
  final outputLimit = _zipOutputLimit(header, limits, remainingTotalBytes);
  try {
    final dataStart = _zipEntryDataStart(header, archiveBytes);
    final dataEnd = dataStart + header.compressedSize;
    late final Uint8List bytes;
    if (header.compressionMethod == 0) {
      if (header.compressedSize > outputLimit) {
        throw _zipOutputLimitException(header.filename, outputLimit);
      }
      bytes = Uint8List.fromList(archiveBytes.sublist(dataStart, dataEnd));
    } else if (header.compressionMethod == 8) {
      final output = _BoundedZipOutputSink(
        entryName: header.filename,
        maxBytes: outputLimit,
      );
      final inflater = ZLibCodec(
        raw: true,
      ).decoder.startChunkedConversion(output);
      for (
        var offset = dataStart;
        offset < dataEnd;
        offset += _zipInflateInputChunkBytes
      ) {
        final end = offset + _zipInflateInputChunkBytes < dataEnd
            ? offset + _zipInflateInputChunkBytes
            : dataEnd;
        inflater.add(archiveBytes.sublist(offset, end));
      }
      inflater.close();
      bytes = output.takeBytes();
    } else {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP entry uses an unsupported compression method: '
        '${header.filename}',
      );
    }
    if (bytes.length != header.uncompressedSize) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP entry ${header.filename} size does not match its central header.',
      );
    }
    if (_crc32(bytes) != header.crc32) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'ZIP entry ${header.filename} failed its CRC-32 check.',
      );
    }
    return bytes;
  } catch (error, stackTrace) {
    if (error is UafException) rethrow;
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unable to decompress ZIP entry: ${header.filename}',
      error,
      stackTrace,
    );
  }
}

int _zipOutputLimit(
  ZipFileHeader header,
  UafPackageReadLimits limits,
  int remainingTotalBytes,
) {
  if (remainingTotalBytes < 0) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP package exceeds the ${limits.maxTotalUncompressedBytes}-byte '
      'uncompressed limit.',
    );
  }

  var outputLimit = header.uncompressedSize;
  if (limits.maxEntryBytes < outputLimit) {
    outputLimit = limits.maxEntryBytes;
  }
  if (remainingTotalBytes < outputLimit) {
    outputLimit = remainingTotalBytes;
  }
  final ratioLimit = header.compressedSize * limits.maxCompressionRatio;
  if (ratioLimit < outputLimit) outputLimit = ratioLimit;
  return outputLimit;
}

int _zipEntryDataStart(ZipFileHeader header, List<int> archiveBytes) {
  final offset = header.localHeaderOffset;
  final nameLength = _readUint16Le(archiveBytes, offset + 26);
  final extraLength = _readUint16Le(archiveBytes, offset + 28);
  final dataStart = offset + 30 + nameLength + extraLength;
  final dataEnd = dataStart + header.compressedSize;
  if (dataStart < offset ||
      dataEnd < dataStart ||
      dataEnd > archiveBytes.length) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'ZIP entry data is outside the archive: ${header.filename}',
    );
  }
  return dataStart;
}

UafException _zipOutputLimitException(String entryName, int outputLimit) {
  return UafException(
    UafErrorCode.invalidPackage,
    'ZIP entry $entryName exceeds its bounded decompression limit of '
    '$outputLimit bytes.',
  );
}

final class _BoundedZipOutputSink implements Sink<List<int>> {
  _BoundedZipOutputSink({required this.entryName, required this.maxBytes});

  final String entryName;
  final int maxBytes;
  final BytesBuilder _bytes = BytesBuilder();
  var _length = 0;
  var _closed = false;

  @override
  void add(List<int> data) {
    if (_closed) throw StateError('ZIP output sink is closed.');
    if (data.length > maxBytes - _length) {
      throw _zipOutputLimitException(entryName, maxBytes);
    }
    _bytes.add(data);
    _length += data.length;
  }

  @override
  void close() {
    _closed = true;
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

const int _zipInflateInputChunkBytes = 4096;

Uint8List _readFileBytes(String filePath, String packagePath, {int? maxBytes}) {
  try {
    if (maxBytes != null && File(filePath).lengthSync() > maxBytes) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Package file $packagePath exceeds the $maxBytes-byte limit.',
      );
    }
    return File(filePath).readAsBytesSync();
  } catch (error, stackTrace) {
    if (error is UafException) rethrow;
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unable to read package file: $packagePath',
      error,
      stackTrace,
    );
  }
}

Uint8List _requiredArtifact(
  Map<String, Uint8List> artifacts,
  String relativePath,
) {
  final bytes = artifacts[relativePath];
  if (bytes == null) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Required artifact is not loaded: $relativePath',
    );
  }
  return bytes;
}

void _ensureSamePayload(
  String sourceName,
  UafDocument expected,
  UafDocument actual,
) {
  if (expected != actual) {
    throw UafException(
      UafErrorCode.invalidPackage,
      '$sourceName payload does not match the canonical CSV payload.',
    );
  }
}

String _decodeUtf8(List<int> bytes, String path) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } catch (error, stackTrace) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Artifact $path must be valid UTF-8.',
      error,
      stackTrace,
    );
  }
}

Uint8List _manifestBytes(UafArtifactManifest manifest) {
  return Uint8List.fromList(utf8.encode('${manifest.toJsonString()}\n'));
}

Uint8List _copyBytes(List<int> bytes) => Uint8List.fromList(bytes);

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    var value = (crc ^ byte) & 0xff;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? (value >> 1) ^ 0xedb88320 : value >> 1;
    }
    crc = (crc >> 8) ^ value;
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

void _requireNonEmptyPath(String path) {
  if (path.trim().isEmpty) {
    throw ArgumentError.value(path, 'path', 'must not be empty');
  }
}

final RegExp _relativePathPattern = RegExp(r'^[A-Za-z0-9._/-]+$');
final RegExp _drivePrefixPattern = RegExp(r'^[A-Za-z]:');
const Set<String> _windowsReservedNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};
