import 'package:unified_assignment_format/unified_assignment_format.dart';

void main() {
  final document = UafDocument(<UafAssignment>[
    UafAssignment(
      subject: '数学',
      date: '2026-05-19',
      content: '完成第1、2题',
      tags: const <String>['必做'],
    ),
  ]);

  final csv = UafCsv.serialize(document);
  final html = UafHtml.render(document);
  final pdf = UafPdf.create(document);
  final manifest = UafArtifactManifest(
    createdAt: DateTime.utc(2026, 7, 13),
    entrypoints: const UafPackageEntrypoints(),
    artifacts: const <UafArtifactEntry>[
      UafArtifactEntry(
        role: 'payload.csv',
        path: 'uaf_payload.csv',
        mediaType: 'text/csv; charset=utf-8',
        bytes: 1,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
      UafArtifactEntry(
        role: 'display.html',
        path: 'display.html',
        mediaType: 'text/html; charset=utf-8',
        bytes: 1,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
      UafArtifactEntry(
        role: 'exchange.pdf',
        path: 'document.pdf',
        mediaType: 'application/pdf',
        bytes: 1,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    ],
    pipeline: const UafPipelineInfo(),
  );
  final restoredManifest = UafArtifactManifest.parseValidated(
    manifest.toJsonString(),
  );
  if (UafCsv.parse(csv) != document ||
      UafHtml.extractPayload(html) != document ||
      UafPdf.extractPayload(pdf) != document ||
      restoredManifest != manifest) {
    throw StateError('UAF platform-neutral round-trip failed.');
  }
}
