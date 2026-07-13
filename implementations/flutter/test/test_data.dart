import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unified_assignment_format/unified_assignment_format.dart';

UafDocument sampleDocument() => UafDocument(<UafAssignment>[
  UafAssignment(
    subject: '数学',
    date: '2026-05-19',
    content: '完成第1、2题',
    tags: const <String>['必做', '几何'],
  ),
  UafAssignment(
    subject: '语文',
    date: '2026-05-19T08:30:00+08:00',
    content: '背诵古诗\n完成仿写',
    tags: const <String>['背诵'],
  ),
  UafAssignment(subject: '英语', date: '2026-05-19', content: 'Read Unit 3'),
]);

String repositoryPath(String relativePath) =>
    p.normalize(p.join(Directory.current.path, '..', '..', relativePath));

Matcher throwsUaf(UafErrorCode code) => throwsA(
  isA<UafException>().having((UafException error) => error.code, 'code', code),
);
