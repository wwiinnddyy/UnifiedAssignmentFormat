import 'dart:convert';

import 'constants.dart';
import 'errors.dart';

/// Immutable description of a UAF artifact package.
final class UafArtifactManifest {
  /// Creates a manifest value.
  UafArtifactManifest({
    this.schema,
    this.schemaVersion = '1.0',
    this.packageKind = 'uaf-artifact-set',
    this.uafVersion = '1.0',
    required this.createdAt,
    required this.entrypoints,
    required Iterable<UafArtifactEntry> artifacts,
    required this.pipeline,
  }) : artifacts = List<UafArtifactEntry>.unmodifiable(artifacts);

  /// Parses a manifest from a decoded JSON object.
  factory UafArtifactManifest.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      r'$schema',
      'schemaVersion',
      'packageKind',
      'uafVersion',
      'createdAt',
      'entrypoints',
      'artifacts',
      'pipeline',
    }, 'manifest');

    final schemaValue = json[r'$schema'];
    if (schemaValue != null && schemaValue is! String) {
      throw const FormatException(r'Manifest "$schema" must be a string.');
    }

    final artifactValues = _requiredList(json, 'artifacts', 'manifest');
    return UafArtifactManifest(
      schema: schemaValue as String?,
      schemaVersion: _requiredString(json, 'schemaVersion', 'manifest'),
      packageKind: _requiredString(json, 'packageKind', 'manifest'),
      uafVersion: _requiredString(json, 'uafVersion', 'manifest'),
      createdAt: _requiredDateTime(json, 'createdAt', 'manifest'),
      entrypoints: UafPackageEntrypoints.fromJson(
        _requiredObject(json, 'entrypoints', 'manifest'),
      ),
      artifacts: artifactValues.map((Object? value) {
        if (value is! Map) {
          throw const FormatException(
            'Manifest artifacts entries must be JSON objects.',
          );
        }
        return UafArtifactEntry.fromJson(_stringKeyedMap(value, 'artifact'));
      }),
      pipeline: UafPipelineInfo.fromJson(
        _requiredObject(json, 'pipeline', 'manifest'),
      ),
    );
  }

  /// Parses a manifest from UTF-8 JSON text.
  factory UafArtifactManifest.fromJsonString(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Manifest JSON root must be an object.');
    }
    return UafArtifactManifest.fromJson(_stringKeyedMap(decoded, 'manifest'));
  }

  /// Parses and fully validates a manifest using the UAF v1.0 package rules.
  ///
  /// Unlike [fromJsonString], this factory checks semantic constants, roles,
  /// media types, entrypoint contracts, digests, and portable relative paths.
  /// It is platform-neutral and can be used by Flutter Web clients.
  factory UafArtifactManifest.parseValidated(String source) {
    late final UafArtifactManifest manifest;
    try {
      manifest = UafArtifactManifest.fromJsonString(source);
    } catch (error, stackTrace) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Manifest JSON is invalid.',
        error,
        stackTrace,
      );
    }
    manifest.validate();
    return manifest;
  }

  /// Optional URI or relative reference to the manifest JSON Schema.
  final String? schema;

  /// Artifact manifest schema version.
  final String schemaVersion;

  /// Fixed package discriminator (`uaf-artifact-set`).
  final String packageKind;

  /// Version of the UAF payload and rendering standard.
  final String uafVersion;

  /// Time at which the package was produced.
  final DateTime createdAt;

  /// Paths of the three required package entry points.
  final UafPackageEntrypoints entrypoints;

  /// Every non-manifest file stored in the package.
  final List<UafArtifactEntry> artifacts;

  /// Description of the display/PDF production pipeline.
  final UafPipelineInfo pipeline;

  /// Converts this value to a JSON-compatible object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (schema != null) r'$schema': schema,
    'schemaVersion': schemaVersion,
    'packageKind': packageKind,
    'uafVersion': uafVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'entrypoints': entrypoints.toJson(),
    'artifacts': artifacts
        .map((UafArtifactEntry artifact) => artifact.toJson())
        .toList(growable: false),
    'pipeline': pipeline.toJson(),
  };

  /// Serializes this value as JSON.
  String toJsonString({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// Validates this manifest using the complete platform-neutral UAF rules.
  void validate() => _validateManifest(this);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UafArtifactManifest &&
            schema == other.schema &&
            schemaVersion == other.schemaVersion &&
            packageKind == other.packageKind &&
            uafVersion == other.uafVersion &&
            createdAt.toUtc() == other.createdAt.toUtc() &&
            entrypoints == other.entrypoints &&
            _listEquals(artifacts, other.artifacts) &&
            pipeline == other.pipeline;
  }

  @override
  int get hashCode => Object.hash(
    schema,
    schemaVersion,
    packageKind,
    uafVersion,
    createdAt.toUtc(),
    entrypoints,
    Object.hashAll(artifacts),
    pipeline,
  );
}

/// Immutable paths of the required UAF package entry points.
final class UafPackageEntrypoints {
  /// Creates an entry-point set.
  const UafPackageEntrypoints({
    this.payload = 'uaf_payload.csv',
    this.display = 'display.html',
    this.exchange = 'document.pdf',
  });

  /// Parses entry points from a decoded JSON object.
  factory UafPackageEntrypoints.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'payload',
      'display',
      'exchange',
    }, 'entrypoints');
    return UafPackageEntrypoints(
      payload: _requiredString(json, 'payload', 'entrypoints'),
      display: _requiredString(json, 'display', 'entrypoints'),
      exchange: _requiredString(json, 'exchange', 'entrypoints'),
    );
  }

  /// Machine-readable CSV entry point.
  final String payload;

  /// Self-contained HTML display entry point.
  final String display;

  /// Official PDF exchange entry point.
  final String exchange;

  /// Converts this value to a JSON-compatible object.
  Map<String, Object> toJson() => <String, Object>{
    'payload': payload,
    'display': display,
    'exchange': exchange,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UafPackageEntrypoints &&
            payload == other.payload &&
            display == other.display &&
            exchange == other.exchange;
  }

  @override
  int get hashCode => Object.hash(payload, display, exchange);
}

/// Immutable integrity record for one packaged file.
final class UafArtifactEntry {
  /// Creates an artifact entry.
  const UafArtifactEntry({
    required this.role,
    required this.path,
    required this.mediaType,
    required this.bytes,
    required this.sha256,
  });

  /// Parses an artifact entry from a decoded JSON object.
  factory UafArtifactEntry.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'role',
      'path',
      'mediaType',
      'bytes',
      'sha256',
    }, 'artifact');
    return UafArtifactEntry(
      role: _requiredString(json, 'role', 'artifact'),
      path: _requiredString(json, 'path', 'artifact'),
      mediaType: _requiredString(json, 'mediaType', 'artifact'),
      bytes: _requiredInt(json, 'bytes', 'artifact'),
      sha256: _requiredString(json, 'sha256', 'artifact'),
    );
  }

  /// Semantic role (`payload.csv`, `display.html`, `exchange.pdf`, or
  /// `supporting`).
  final String role;

  /// Safe, `/`-separated relative path inside the package.
  final String path;

  /// Declared media type.
  final String mediaType;

  /// Uncompressed byte length.
  final int bytes;

  /// Lowercase hexadecimal SHA-256 digest.
  final String sha256;

  /// Converts this value to a JSON-compatible object.
  Map<String, Object> toJson() => <String, Object>{
    'role': role,
    'path': path,
    'mediaType': mediaType,
    'bytes': bytes,
    'sha256': sha256,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UafArtifactEntry &&
            role == other.role &&
            path == other.path &&
            mediaType == other.mediaType &&
            bytes == other.bytes &&
            sha256 == other.sha256;
  }

  @override
  int get hashCode => Object.hash(role, path, mediaType, bytes, sha256);
}

/// Immutable description of the renderer that produced a UAF package.
final class UafPipelineInfo {
  /// Creates pipeline metadata.
  const UafPipelineInfo({
    this.renderer = 'native-pdf',
    this.printEngine = 'dart-native',
    this.payloadAttachment = 'uaf_payload.csv',
  });

  /// Parses pipeline metadata from a decoded JSON object.
  factory UafPipelineInfo.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'renderer',
      'printEngine',
      'payloadAttachment',
    }, 'pipeline');
    return UafPipelineInfo(
      renderer: _requiredString(json, 'renderer', 'pipeline'),
      printEngine: _requiredString(json, 'printEngine', 'pipeline'),
      payloadAttachment: _requiredString(json, 'payloadAttachment', 'pipeline'),
    );
  }

  /// Rendering strategy (`html-to-pdf` or `native-pdf`).
  final String renderer;

  /// Concrete print/PDF engine named by the schema.
  final String printEngine;

  /// Required embedded payload file name.
  final String payloadAttachment;

  /// Converts this value to a JSON-compatible object.
  Map<String, Object> toJson() => <String, Object>{
    'renderer': renderer,
    'printEngine': printEngine,
    'payloadAttachment': payloadAttachment,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UafPipelineInfo &&
            renderer == other.renderer &&
            printEngine == other.printEngine &&
            payloadAttachment == other.payloadAttachment;
  }

  @override
  int get hashCode => Object.hash(renderer, printEngine, payloadAttachment);
}

void _validateManifest(UafArtifactManifest manifest) {
  if (manifest.schemaVersion != UafConstants.version) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unsupported manifest schemaVersion: ${manifest.schemaVersion}',
    );
  }
  if (manifest.packageKind != 'uaf-artifact-set') {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unsupported packageKind: ${manifest.packageKind}',
    );
  }
  if (manifest.uafVersion != UafConstants.version) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unsupported uafVersion: ${manifest.uafVersion}',
    );
  }

  const renderers = <String>{'html-to-pdf', 'native-pdf'};
  const printEngines = <String>{
    'browser-print',
    'pdf-lib',
    'dotnet-native',
    'dart-native',
  };
  if (!renderers.contains(manifest.pipeline.renderer)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unsupported pipeline renderer: ${manifest.pipeline.renderer}',
    );
  }
  if (!printEngines.contains(manifest.pipeline.printEngine)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unsupported pipeline printEngine: ${manifest.pipeline.printEngine}',
    );
  }
  if (manifest.pipeline.payloadAttachment != UafConstants.payloadFileName) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'Manifest pipeline payloadAttachment must be uaf_payload.csv.',
    );
  }

  _requireEntrypoint(
    'payload',
    manifest.entrypoints.payload,
    UafConstants.payloadFileName,
  );
  _requireEntrypoint(
    'display',
    manifest.entrypoints.display,
    UafConstants.displayFileName,
  );
  _requireEntrypoint(
    'exchange',
    manifest.entrypoints.exchange,
    UafConstants.exchangePdfFileName,
  );

  if (manifest.artifacts.length < 3) {
    throw const UafException(
      UafErrorCode.invalidPackage,
      'Manifest must list at least three artifacts.',
    );
  }

  final paths = <String>{};
  final requiredByRole = <String, UafArtifactEntry>{};
  for (final artifact in manifest.artifacts) {
    _validateArtifact(artifact);
    if (!paths.add(artifact.path)) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Duplicate artifact path: ${artifact.path}',
      );
    }
    if (artifact.path == UafConstants.manifestFileName) {
      throw const UafException(
        UafErrorCode.invalidPackage,
        'uaf-manifest.json must not list itself as an artifact.',
      );
    }
    if (artifact.role != 'supporting') {
      if (requiredByRole.containsKey(artifact.role)) {
        throw UafException(
          UafErrorCode.invalidPackage,
          'Duplicate required artifact role: ${artifact.role}',
        );
      }
      requiredByRole[artifact.role] = artifact;
    }
  }
  _validatePortableFileSet(<String>{
    UafConstants.manifestFileName,
    ...manifest.artifacts.map((UafArtifactEntry artifact) => artifact.path),
  });

  _requireArtifactContract(
    requiredByRole,
    'payload.csv',
    UafConstants.payloadFileName,
    'text/csv; charset=utf-8',
  );
  _requireArtifactContract(
    requiredByRole,
    'display.html',
    UafConstants.displayFileName,
    'text/html; charset=utf-8',
  );
  _requireArtifactContract(
    requiredByRole,
    'exchange.pdf',
    UafConstants.exchangePdfFileName,
    'application/pdf',
  );

  final entrypointRoles = <String, String>{
    manifest.entrypoints.payload: 'payload.csv',
    manifest.entrypoints.display: 'display.html',
    manifest.entrypoints.exchange: 'exchange.pdf',
  };
  for (final entry in entrypointRoles.entries) {
    UafArtifactEntry? artifact;
    for (final candidate in manifest.artifacts) {
      if (candidate.path == entry.key) {
        artifact = candidate;
        break;
      }
    }
    if (artifact == null || artifact.role != entry.value) {
      throw UafException(
        UafErrorCode.invalidPackage,
        'Manifest entrypoint ${entry.key} must reference role ${entry.value}.',
      );
    }
  }
}

void _validateArtifact(UafArtifactEntry artifact) {
  const roles = <String>{
    'payload.csv',
    'display.html',
    'exchange.pdf',
    'supporting',
  };
  if (!roles.contains(artifact.role)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Unsupported artifact role: ${artifact.role}',
    );
  }
  _ensureSafeRelativePath(artifact.path);
  if (artifact.mediaType.trim().isEmpty) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Artifact ${artifact.path} must declare mediaType.',
    );
  }
  if (artifact.bytes < 0) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Artifact ${artifact.path} has invalid byte length.',
    );
  }
  if (!_sha256Pattern.hasMatch(artifact.sha256)) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Artifact ${artifact.path} has invalid sha256.',
    );
  }
}

void _requireEntrypoint(String name, String actual, String required) {
  _ensureSafeRelativePath(actual);
  if (actual != required) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Manifest entrypoints.$name must be $required.',
    );
  }
}

void _requireArtifactContract(
  Map<String, UafArtifactEntry> byRole,
  String role,
  String requiredPath,
  String requiredMediaType,
) {
  final artifact = byRole[role];
  if (artifact == null) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Manifest is missing required role: $role',
    );
  }
  if (artifact.path != requiredPath) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Artifact role $role must use path $requiredPath.',
    );
  }
  if (artifact.mediaType.toLowerCase() != requiredMediaType.toLowerCase()) {
    throw UafException(
      UafErrorCode.invalidPackage,
      'Artifact $requiredPath must use mediaType $requiredMediaType.',
    );
  }
}

void _ensureSafeRelativePath(String relativePath) {
  final segments = relativePath.split('/');
  if (relativePath.isEmpty ||
      relativePath.contains('\\') ||
      relativePath.contains('://') ||
      relativePath.startsWith('/') ||
      _drivePrefixPattern.hasMatch(relativePath) ||
      !_relativePathPattern.hasMatch(relativePath) ||
      segments.length > _maxPathDepth ||
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

void _validatePortableFileSet(Iterable<String> paths) {
  final byPortableKey = <String, String>{};
  final keys = <String>{};
  for (final path in paths) {
    _ensureSafeRelativePath(path);
    final key = path.toLowerCase();
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

bool _isWindowsReservedSegment(String segment) {
  final baseName = segment.split('.').first.toUpperCase();
  return _windowsReservedNames.contains(baseName);
}

Map<String, Object?> _stringKeyedMap(
  Map<Object?, Object?> source,
  String name,
) {
  final result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in source.entries) {
    if (entry.key is! String) {
      throw FormatException('$name JSON keys must be strings.');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

void _requireOnlyKeys(
  Map<String, Object?> source,
  Set<String> allowed,
  String name,
) {
  for (final key in source.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('Unknown $name property: $key.');
    }
  }
}

String _requiredString(Map<String, Object?> source, String key, String name) {
  final value = source[key];
  if (value is! String) {
    throw FormatException('$name.$key must be a string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> source, String key, String name) {
  final value = source[key];
  if (value is! int) {
    throw FormatException('$name.$key must be an integer.');
  }
  return value;
}

List<Object?> _requiredList(
  Map<String, Object?> source,
  String key,
  String name,
) {
  final value = source[key];
  if (value is! List) {
    throw FormatException('$name.$key must be an array.');
  }
  return List<Object?>.of(value);
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> source,
  String key,
  String name,
) {
  final value = source[key];
  if (value is! Map) {
    throw FormatException('$name.$key must be an object.');
  }
  return _stringKeyedMap(value, '$name.$key');
}

DateTime _requiredDateTime(
  Map<String, Object?> source,
  String key,
  String name,
) {
  final value = _requiredString(source, key, name);
  final match = _dateTimePattern.firstMatch(value);
  if (match == null) {
    throw FormatException('$name.$key must be an ISO 8601 date-time.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final offsetHour = int.tryParse(match.group(9) ?? '0') ?? 0;
  final offsetMinute = int.tryParse(match.group(10) ?? '0') ?? 0;
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > _daysInMonth(year, month) ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    throw FormatException('$name.$key must be an ISO 8601 date-time.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$name.$key must be an ISO 8601 date-time.');
  }
  return parsed;
}

int _daysInMonth(int year, int month) {
  const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month != 2) return days[month - 1];
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  return leap ? 29 : 28;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final RegExp _dateTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
  r'(?:\.(\d+))?(?:Z|([+-])(\d{2}):(\d{2}))$',
);
final RegExp _relativePathPattern = RegExp(r'^[A-Za-z0-9._/-]+$');
final RegExp _drivePrefixPattern = RegExp(r'^[A-Za-z]:');
final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
const int _maxPathDepth = 16;
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
