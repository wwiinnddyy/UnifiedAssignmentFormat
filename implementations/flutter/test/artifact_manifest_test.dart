import 'dart:convert';

import 'package:test/test.dart';
import 'package:unified_assignment_format/unified_assignment_format.dart';

const String _digest =
    '0000000000000000000000000000000000000000000000000000000000000000';

void main() {
  group('UAF artifact manifest', () {
    test('validates a complete manifest through the platform-neutral API', () {
      final manifest = _validManifest();

      expect(() => manifest.validate(), returnsNormally);
      expect(
        UafArtifactManifest.parseValidated(manifest.toJsonString()),
        manifest,
      );
    });

    test('rejects semantic and portable-path violations', () {
      final validJson = _validManifest().toJson();
      final invalidValues = <Map<String, Object?>>[
        <String, Object?>{...validJson, 'schemaVersion': '2.0'},
        <String, Object?>{
          ...validJson,
          'pipeline': <String, Object?>{
            'renderer': 'native-pdf',
            'printEngine': 'unknown-engine',
            'payloadAttachment': UafConstants.payloadFileName,
          },
        },
        <String, Object?>{
          ...validJson,
          'artifacts': <Object?>[
            ...(validJson['artifacts']! as List<Object?>),
            <String, Object?>{
              'role': 'supporting',
              'path': '../escape.txt',
              'mediaType': 'text/plain',
              'bytes': 0,
              'sha256': _digest,
            },
          ],
        },
        <String, Object?>{
          ...validJson,
          'artifacts': <Object?>[
            ...(validJson['artifacts']! as List<Object?>),
            <String, Object?>{
              'role': 'supporting',
              'path': 'AUX.txt',
              'mediaType': 'text/plain',
              'bytes': 0,
              'sha256': _digest,
            },
          ],
        },
      ];

      for (final value in invalidValues) {
        expect(
          () => UafArtifactManifest.parseValidated(jsonEncode(value)),
          _throwsUaf(UafErrorCode.invalidPackage),
        );
      }
    });
  });
}

UafArtifactManifest _validManifest() {
  return UafArtifactManifest(
    createdAt: DateTime.utc(2026, 7, 13),
    entrypoints: const UafPackageEntrypoints(),
    artifacts: const <UafArtifactEntry>[
      UafArtifactEntry(
        role: 'payload.csv',
        path: 'uaf_payload.csv',
        mediaType: 'text/csv; charset=utf-8',
        bytes: 1,
        sha256: _digest,
      ),
      UafArtifactEntry(
        role: 'display.html',
        path: 'display.html',
        mediaType: 'text/html; charset=utf-8',
        bytes: 1,
        sha256: _digest,
      ),
      UafArtifactEntry(
        role: 'exchange.pdf',
        path: 'document.pdf',
        mediaType: 'application/pdf',
        bytes: 1,
        sha256: _digest,
      ),
    ],
    pipeline: const UafPipelineInfo(),
  );
}

Matcher _throwsUaf(UafErrorCode code) => throwsA(
  isA<UafException>().having((UafException error) => error.code, 'code', code),
);
