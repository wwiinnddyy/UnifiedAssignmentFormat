import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unified_assignment_format/unified_assignment_format_io.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'uaf-artifact-package-',
    );
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('create is deterministic and declares the Dart-native pipeline', () {
    final payload = _sampleDocument();
    final createdAt = DateTime.utc(2026, 7, 13, 12, 34, 56);
    final first = UafArtifactPackage.create(payload, createdAt: createdAt);
    final second = UafArtifactPackage.create(payload, createdAt: createdAt);

    expect(first.payload, payload);
    expect(first.manifest, second.manifest);
    expect(
      UafArtifactManifest.fromJsonString(first.manifest.toJsonString()),
      first.manifest,
    );
    expect(first.manifest.schemaVersion, UafConstants.version);
    expect(first.manifest.packageKind, 'uaf-artifact-set');
    expect(first.manifest.uafVersion, UafConstants.version);
    expect(first.manifest.createdAt, createdAt);
    expect(first.manifest.entrypoints, const UafPackageEntrypoints());
    expect(first.manifest.pipeline.renderer, 'native-pdf');
    expect(first.manifest.pipeline.printEngine, 'dart-native');
    expect(
      first.manifest.pipeline.payloadAttachment,
      UafConstants.payloadFileName,
    );
    expect(
      first.manifest.artifacts.map((UafArtifactEntry entry) => entry.role),
      orderedEquals(<String>['payload.csv', 'display.html', 'exchange.pdf']),
    );

    for (final artifact in first.manifest.artifacts) {
      final bytes = first.getArtifact(artifact.path);
      expect(artifact.bytes, bytes.length);
      expect(artifact.sha256, sha256.convert(bytes).toString());
      expect(bytes, orderedEquals(second.getArtifact(artifact.path)));
    }
  });

  test('round-trips a verified package through in-memory ZIP bytes', () {
    final original = UafArtifactPackage.create(
      _sampleDocument(),
      createdAt: DateTime.utc(2026, 7, 13),
    );

    final restored = UafArtifactPackage.fromBytes(original.toZipBytes());

    expect(restored.manifest, original.manifest);
    expect(restored.payload, original.payload);
    expect(restored.csv, original.csv);
    expect(restored.html, original.html);
    expect(restored.pdfBytes, orderedEquals(original.pdfBytes));
  });

  test('round-trips stored ZIP entries without deflate', () {
    final original = UafArtifactPackage.create(
      _sampleDocument(),
      createdAt: DateTime.utc(2026, 7, 13),
    );
    final archive = Archive();
    final manifestBytes = Uint8List.fromList(
      utf8.encode('${original.manifest.toJsonString()}\n'),
    );
    archive.addFile(
      ArchiveFile(
        UafConstants.manifestFileName,
        manifestBytes.length,
        manifestBytes,
      )..compression = CompressionType.none,
    );
    for (final artifact in original.manifest.artifacts) {
      final bytes = original.getArtifact(artifact.path);
      archive.addFile(
        ArchiveFile(artifact.path, bytes.length, bytes)
          ..compression = CompressionType.none,
      );
    }

    final restored = UafArtifactPackage.fromBytes(
      ZipEncoder().encodeBytes(archive),
    );
    expect(restored.payload, original.payload);
    expect(restored.pdfBytes, orderedEquals(original.pdfBytes));
  });

  test('enforces ZIP input and entry resource limits', () async {
    final bytes = UafArtifactPackage.create(_sampleDocument()).toZipBytes();

    expect(
      () => UafArtifactPackage.fromBytes(
        bytes,
        limits: UafPackageReadLimits(maxZipBytes: bytes.length - 1),
      ),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
    expect(
      () => UafArtifactPackage.fromBytes(
        bytes,
        limits: const UafPackageReadLimits(maxEntryBytes: 64),
      ),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
    expect(
      () => UafArtifactPackage.fromBytes(
        bytes,
        limits: const UafPackageReadLimits(maxCompressionRatio: 1),
      ),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
    await expectLater(
      UafArtifactPackage.fromBytesAsync(
        bytes,
        limits: UafPackageReadLimits(maxZipBytes: bytes.length - 1),
      ),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('enforces directory manifest and aggregate resource limits', () {
    final package = UafArtifactPackage.create(_sampleDocument());
    final directoryPath = p.join(temporaryDirectory.path, 'limited.uaf');
    package.writeDirectory(directoryPath);

    final manifestFile = File(
      p.join(directoryPath, UafConstants.manifestFileName),
    );
    final manifestLength = manifestFile.lengthSync();
    var artifactTotal = 0;
    var largestArtifact = 0;
    for (final artifact in package.manifest.artifacts) {
      artifactTotal += artifact.bytes;
      if (artifact.bytes > largestArtifact) largestArtifact = artifact.bytes;
    }
    expect(manifestLength, lessThan(largestArtifact));

    expect(
      () => UafArtifactPackage.readDirectory(
        directoryPath,
        limits: UafPackageReadLimits(
          maxEntryBytes: largestArtifact,
          maxTotalUncompressedBytes: artifactTotal,
        ),
      ),
      _throwsUaf(UafErrorCode.invalidPackage),
    );

    final manifestText = manifestFile.readAsStringSync();
    manifestFile.writeAsStringSync(
      '$manifestText${List<String>.filled(largestArtifact - manifestLength + 1, ' ').join()}',
    );
    expect(
      () => UafArtifactPackage.readDirectory(
        directoryPath,
        limits: UafPackageReadLimits(maxEntryBytes: largestArtifact),
      ),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('stops forged deflate output at the bounded declared size', () {
    const limits = UafPackageReadLimits(
      maxEntryBytes: 64,
      maxTotalUncompressedBytes: 64,
    );
    final compressed = ZLibCodec(raw: true).encode(Uint8List(1024 * 1024));
    final forged = _singleEntryZip(
      name: UafConstants.manifestFileName,
      compressionMethod: 8,
      compressedBytes: compressed,
      declaredUncompressedSize: 32,
    );

    expect(
      () => UafArtifactPackage.fromBytes(forged, limits: limits),
      throwsA(
        isA<UafException>()
            .having(
              (UafException error) => error.code,
              'code',
              UafErrorCode.invalidPackage,
            )
            .having(
              (UafException error) => error.message,
              'message',
              contains('bounded decompression limit of 32 bytes'),
            ),
      ),
    );

    final forgedStored = _singleEntryZip(
      name: UafConstants.manifestFileName,
      compressionMethod: 0,
      compressedBytes: Uint8List(64),
      declaredUncompressedSize: 32,
    );
    expect(
      () => UafArtifactPackage.fromBytes(forgedStored, limits: limits),
      throwsA(
        isA<UafException>().having(
          (UafException error) => error.message,
          'message',
          contains('Stored ZIP entry has inconsistent'),
        ),
      ),
    );
  });

  test('rejects unsupported ZIP methods and forged CRC values', () {
    final original = UafArtifactPackage.create(_sampleDocument()).toZipBytes();

    final unsupported = Uint8List.fromList(original);
    final local = _findSignature(unsupported, 0x04034b50);
    final central = _findSignature(unsupported, 0x02014b50);
    _writeUint16Le(unsupported, local + 8, 99);
    _writeUint16Le(unsupported, central + 10, 99);
    expect(
      () => UafArtifactPackage.fromBytes(unsupported),
      _throwsUaf(UafErrorCode.invalidPackage),
    );

    final forgedCrc = Uint8List.fromList(original);
    final crc = _readUint32Le(forgedCrc, local + 14) ^ 1;
    _writeUint32Le(forgedCrc, local + 14, crc);
    _writeUint32Le(forgedCrc, central + 16, crc);
    expect(
      () => UafArtifactPackage.fromBytes(forgedCrc),
      _throwsUaf(UafErrorCode.invalidPackage),
    );

    final inconsistentMethod = Uint8List.fromList(original);
    final centralMethod = _readUint16Le(inconsistentMethod, central + 10);
    _writeUint16Le(inconsistentMethod, local + 8, centralMethod == 0 ? 8 : 0);
    expect(
      () => UafArtifactPackage.fromBytes(inconsistentMethod),
      _throwsUaf(UafErrorCode.invalidPackage),
    );

    final symbolicLink = Uint8List.fromList(original);
    _writeUint16Le(symbolicLink, central + 4, (3 << 8) | 20);
    _writeUint32Le(symbolicLink, central + 38, 0xa000 << 16);
    expect(
      () => UafArtifactPackage.fromBytes(symbolicLink),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('rejects portable path collisions in a validated manifest', () {
    final package = UafArtifactPackage.create(_sampleDocument());
    final collisionEntries = <UafArtifactEntry>[
      ...package.manifest.artifacts,
      const UafArtifactEntry(
        role: 'supporting',
        path: 'Notes.txt',
        mediaType: 'text/plain',
        bytes: 0,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
      const UafArtifactEntry(
        role: 'supporting',
        path: 'notes.txt',
        mediaType: 'text/plain',
        bytes: 0,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    ];
    final manifest = UafArtifactManifest(
      createdAt: package.manifest.createdAt,
      entrypoints: package.manifest.entrypoints,
      artifacts: collisionEntries,
      pipeline: package.manifest.pipeline,
    );

    expect(
      () => UafArtifactPackage.validateManifest(manifest),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('round-trips directory and ZIP file package forms', () {
    final original = UafArtifactPackage.create(_sampleDocument());
    final directoryPath = p.join(temporaryDirectory.path, 'roundtrip.uaf');
    final zipPath = p.join(temporaryDirectory.path, 'roundtrip.uaf.zip');

    original.writeDirectory(directoryPath);
    original.writeZip(zipPath);

    expect(
      UafArtifactPackage.readDirectory(directoryPath).payload,
      original.payload,
    );
    expect(UafArtifactPackage.readZip(zipPath).payload, original.payload);
    expect(UafArtifactPackage.read(directoryPath).payload, original.payload);
    expect(UafArtifactPackage.read(zipPath).payload, original.payload);
  });

  test('atomically replaces existing directory and ZIP destinations', () {
    final directoryPath = p.join(temporaryDirectory.path, 'replace.uaf');
    final zipPath = p.join(temporaryDirectory.path, 'replace.uaf.zip');
    UafArtifactPackage.create(_sampleDocument())
      ..writeDirectory(directoryPath)
      ..writeZip(zipPath);

    final replacementDocument = UafDocument(<UafAssignment>[
      UafAssignment(
        subject: 'Replacement',
        date: '2026-07-15',
        content: 'New canonical payload.',
      ),
    ]);
    UafArtifactPackage.create(replacementDocument)
      ..writeDirectory(directoryPath, overwrite: true)
      ..writeZip(zipPath, overwrite: true);

    expect(
      UafArtifactPackage.readDirectory(directoryPath).payload,
      replacementDocument,
    );
    expect(UafArtifactPackage.readZip(zipPath).payload, replacementDocument);
    expect(
      temporaryDirectory
          .listSync()
          .map((FileSystemEntity entity) => p.basename(entity.path))
          .where(
            (String name) =>
                name.contains('.uaf-backup-') || name.contains('.uaf-tmp-'),
          ),
      isEmpty,
    );
  });

  test('supports isolate-based ZIP verification', () async {
    final original = UafArtifactPackage.create(_sampleDocument());
    final restored = await UafArtifactPackage.fromBytesAsync(
      original.toZipBytes(),
    );
    expect(restored.payload, original.payload);

    final directoryPath = p.join(temporaryDirectory.path, 'async.uaf');
    final zipPath = p.join(temporaryDirectory.path, 'async.uaf.zip');
    original.writeDirectory(directoryPath);
    original.writeZip(zipPath);
    expect(
      (await UafArtifactPackage.readAsync(directoryPath)).payload,
      original.payload,
    );
    expect(
      (await UafArtifactPackage.readAsync(zipPath)).payload,
      original.payload,
    );
  });

  test('reads the repository shared sample artifact directory', () {
    final sampleDirectory = _findRepositoryPath(
      p.join('examples', 'sample-homework.uaf'),
    );
    final package = UafArtifactPackage.readDirectory(sampleDirectory);
    final expected = UafCsv.parse(
      File(
        p.join(sampleDirectory, UafConstants.payloadFileName),
      ).readAsStringSync(),
    );

    expect(package.payload, expected);
    expect(package.manifest.pipeline.renderer, 'html-to-pdf');
    expect(package.manifest.pipeline.printEngine, 'browser-print');
    expect(package.pdfBytes, isNotEmpty);
  });

  test('rejects an artifact whose bytes no longer match its hash record', () {
    final directoryPath = _writeSampleDirectory(
      temporaryDirectory,
      'tampered.uaf',
    );
    File(
      p.join(directoryPath, UafConstants.payloadFileName),
    ).writeAsStringSync('tampered', mode: FileMode.append);

    expect(
      () => UafArtifactPackage.readDirectory(directoryPath),
      _throwsUaf(UafErrorCode.hashMismatch),
    );
  });

  test('rejects valid artifacts whose restored payloads disagree', () {
    final directoryPath = _writeSampleDirectory(
      temporaryDirectory,
      'payload-mismatch.uaf',
    );
    final replacement = UafHtml.render(
      UafDocument(<UafAssignment>[
        UafAssignment(
          subject: 'Different',
          date: '2026-07-13',
          content: 'This payload is valid but not canonical.',
        ),
      ]),
    );
    final replacementBytes = utf8.encode(replacement);
    File(
      p.join(directoryPath, UafConstants.displayFileName),
    ).writeAsBytesSync(replacementBytes);

    final manifestFile = File(
      p.join(directoryPath, UafConstants.manifestFileName),
    );
    final manifest = _decodeObject(manifestFile.readAsStringSync());
    final artifacts = manifest['artifacts']! as List<Object?>;
    final displayEntry = artifacts.cast<Map<String, Object?>>().singleWhere(
      (Map<String, Object?> entry) => entry['role'] == 'display.html',
    );
    displayEntry
      ..['bytes'] = replacementBytes.length
      ..['sha256'] = sha256.convert(replacementBytes).toString();
    manifestFile.writeAsStringSync('${jsonEncode(manifest)}\n');

    expect(
      () => UafArtifactPackage.readDirectory(directoryPath),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('rejects a package containing an unlisted file', () {
    final directoryPath = _writeSampleDirectory(
      temporaryDirectory,
      'extra-file.uaf',
    );
    File(p.join(directoryPath, 'unlisted.txt')).writeAsStringSync('unlisted');

    expect(
      () => UafArtifactPackage.readDirectory(directoryPath),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('rejects a manifest artifact path that traverses above the root', () {
    final directoryPath = _writeSampleDirectory(
      temporaryDirectory,
      'traversal.uaf',
    );
    final manifestFile = File(
      p.join(directoryPath, UafConstants.manifestFileName),
    );
    final manifest = _decodeObject(manifestFile.readAsStringSync());
    final artifacts = manifest['artifacts']! as List<Object?>;
    final payloadEntry = artifacts.first as Map<String, Object?>;
    payloadEntry['path'] = '../uaf_payload.csv';
    manifestFile.writeAsStringSync('${jsonEncode(manifest)}\n');

    expect(
      () => UafArtifactPackage.readDirectory(directoryPath),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('rejects invalid manifest JSON', () {
    final directoryPath = _writeSampleDirectory(
      temporaryDirectory,
      'invalid-manifest.uaf',
    );
    File(
      p.join(directoryPath, UafConstants.manifestFileName),
    ).writeAsStringSync('{"schemaVersion":');

    expect(
      () => UafArtifactPackage.readDirectory(directoryPath),
      _throwsUaf(UafErrorCode.invalidPackage),
    );
  });

  test('rejects non-RFC3339 comma fractional seconds', () {
    final json = UafArtifactPackage.create(
      _sampleDocument(),
      createdAt: DateTime.utc(2026, 7, 13, 0, 0, 0, 123),
    ).manifest.toJsonString().replaceFirst('.123Z', ',123Z');

    expect(
      () => UafArtifactManifest.fromJsonString(json),
      throwsFormatException,
    );
  });
}

String _writeSampleDirectory(Directory parent, String name) {
  final directoryPath = p.join(parent.path, name);
  UafArtifactPackage.create(
    _sampleDocument(),
    createdAt: DateTime.utc(2026, 7, 13),
  ).writeDirectory(directoryPath);
  return directoryPath;
}

UafDocument _sampleDocument() {
  return UafDocument(<UafAssignment>[
    UafAssignment(
      subject: 'Mathematics',
      date: '2026-07-13',
      content: 'Complete exercises 1-3.',
      tags: const <String>['homework', 'algebra'],
    ),
    UafAssignment(
      subject: 'Science',
      date: '2026-07-14T09:30:00+09:00',
      content: 'Record the lab observations.',
      tags: const <String>['lab'],
    ),
  ]);
}

Map<String, Object?> _decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw StateError('Expected a JSON object.');
  }
  return decoded;
}

String _findRepositoryPath(String relativePath) {
  var cursor = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = p.join(cursor.path, relativePath);
    if (Directory(candidate).existsSync() || File(candidate).existsSync()) {
      return candidate;
    }
    final parent = cursor.parent;
    if (p.equals(parent.path, cursor.path)) break;
    cursor = parent;
  }
  throw StateError('Repository path not found: $relativePath');
}

Matcher _throwsUaf(UafErrorCode code) {
  return throwsA(
    isA<UafException>().having(
      (UafException error) => error.code,
      'code',
      code,
    ),
  );
}

int _findSignature(Uint8List bytes, int signature) {
  for (var index = 0; index <= bytes.length - 4; index++) {
    if (_readUint32Le(bytes, index) == signature) return index;
  }
  throw StateError('ZIP signature not found: $signature');
}

int _readUint32Le(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

int _readUint16Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

void _writeUint16Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}

Uint8List _singleEntryZip({
  required String name,
  required int compressionMethod,
  required List<int> compressedBytes,
  required int declaredUncompressedSize,
}) {
  final nameBytes = ascii.encode(name);
  final local = BytesBuilder(copy: false)
    ..add(_uint32Le(0x04034b50))
    ..add(_uint16Le(20))
    ..add(_uint16Le(0))
    ..add(_uint16Le(compressionMethod))
    ..add(_uint16Le(0))
    ..add(_uint16Le(0))
    ..add(_uint32Le(0))
    ..add(_uint32Le(compressedBytes.length))
    ..add(_uint32Le(declaredUncompressedSize))
    ..add(_uint16Le(nameBytes.length))
    ..add(_uint16Le(0))
    ..add(nameBytes)
    ..add(compressedBytes);
  final localBytes = local.takeBytes();

  final central = BytesBuilder(copy: false)
    ..add(_uint32Le(0x02014b50))
    ..add(_uint16Le(20))
    ..add(_uint16Le(20))
    ..add(_uint16Le(0))
    ..add(_uint16Le(compressionMethod))
    ..add(_uint16Le(0))
    ..add(_uint16Le(0))
    ..add(_uint32Le(0))
    ..add(_uint32Le(compressedBytes.length))
    ..add(_uint32Le(declaredUncompressedSize))
    ..add(_uint16Le(nameBytes.length))
    ..add(_uint16Le(0))
    ..add(_uint16Le(0))
    ..add(_uint16Le(0))
    ..add(_uint16Le(0))
    ..add(_uint32Le(0))
    ..add(_uint32Le(0))
    ..add(nameBytes);
  final centralBytes = central.takeBytes();

  final end = BytesBuilder(copy: false)
    ..add(_uint32Le(0x06054b50))
    ..add(_uint16Le(0))
    ..add(_uint16Le(0))
    ..add(_uint16Le(1))
    ..add(_uint16Le(1))
    ..add(_uint32Le(centralBytes.length))
    ..add(_uint32Le(localBytes.length))
    ..add(_uint16Le(0));

  return (BytesBuilder(copy: false)
        ..add(localBytes)
        ..add(centralBytes)
        ..add(end.takeBytes()))
      .takeBytes();
}

Uint8List _uint16Le(int value) =>
    Uint8List.fromList(<int>[value & 0xff, (value >> 8) & 0xff]);

Uint8List _uint32Le(int value) => Uint8List.fromList(<int>[
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
]);
