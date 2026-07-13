import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unified_assignment_format/unified_assignment_format_io.dart';

void main() {
  final document = UafDocument(<UafAssignment>[
    UafAssignment(
      subject: '数学',
      date: '2026-05-19',
      content: '完成课本第45页第1、2题，请拍照上传。',
      tags: const <String>['必做', '几何'],
    ),
    UafAssignment(
      subject: '语文',
      date: '2026-05-19',
      content: '背诵《静夜思》\n完成第二段仿写。',
      tags: const <String>['背诵'],
    ),
  ]);

  final csv = UafCsv.serialize(document);
  final html = UafHtml.render(document);
  final pdf = UafPdf.create(document);
  final artifactPackage = UafArtifactPackage.create(document);
  final outputDirectory = Directory(p.join('build', 'example'))
    ..createSync(recursive: true);

  File(
    p.join(outputDirectory.path, UafConstants.payloadFileName),
  ).writeAsStringSync(csv, flush: true);
  File(
    p.join(outputDirectory.path, UafConstants.displayFileName),
  ).writeAsStringSync(html, flush: true);
  File(
    p.join(outputDirectory.path, UafConstants.exchangePdfFileName),
  ).writeAsBytesSync(pdf, flush: true);
  final zipPath = p.join(outputDirectory.path, 'homework.uaf.zip');
  artifactPackage.writeZip(zipPath, overwrite: true);

  final restored = UafArtifactPackage.readZip(zipPath).payload;
  stdout.writeln(
    'Created and verified ${restored.length} assignments in '
    '${outputDirectory.path}.',
  );
}
