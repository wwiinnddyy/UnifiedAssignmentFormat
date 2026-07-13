import 'dart:io';

import 'package:test/test.dart';
import 'package:unified_assignment_format/unified_assignment_format.dart';

import 'test_data.dart';

void main() {
  group('UAF model', () {
    test('is immutable and compares by value', () {
      final sourceTags = <String>['必做'];
      final assignment = UafAssignment(
        subject: '数学',
        date: '2026-05-19',
        content: '完成练习',
        tags: sourceTags,
      );
      sourceTags.add('后来添加');

      expect(assignment.tags, const <String>['必做']);
      expect(
        assignment,
        UafAssignment(
          subject: '数学',
          date: '2026-05-19',
          content: '完成练习',
          tags: const <String>['必做'],
        ),
      );
      expect(() => assignment.tags.add('不可变'), throwsUnsupportedError);
      expect(
        () => UafDocument(const <UafAssignment>[]),
        throwsUaf(UafErrorCode.invalidPayload),
      );
    });

    test('enforces field, date, and tag constraints', () {
      expect(
        () => UafAssignment(subject: '', date: '2026-05-19', content: '正文'),
        throwsUaf(UafErrorCode.invalidPayload),
      );
      expect(
        () => UafAssignment(subject: '数学', date: '2026-02-29', content: '正文'),
        throwsUaf(UafErrorCode.invalidPayload),
      );
      expect(
        () => UafAssignment(
          subject: '数学',
          date: '2026-05-19',
          content: '正文',
          tags: const <String>['不允许;分号'],
        ),
        throwsUaf(UafErrorCode.invalidPayload),
      );
      expect(
        () => UafAssignment(
          subject: '数学',
          date: '2026-05-19',
          content: '正文',
          tags: List<String>.generate(21, (int index) => '标签$index'),
        ),
        throwsUaf(UafErrorCode.invalidPayload),
      );
    });
  });

  group('UAF CSV', () {
    test('round-trips multilingual RFC 4180 content', () {
      final document = UafDocument(<UafAssignment>[
        UafAssignment(
          subject: '综合,实践',
          date: '2026-05-19T08:30:00Z',
          content: '第一行,"引用"\r\n第二行 😀',
          tags: const <String>['必做', '项目'],
        ),
      ]);

      final csv = UafCsv.serialize(document);
      expect(csv, startsWith('${UafConstants.csvHeader}\n'));
      expect(csv, contains('"综合,实践"'));
      expect(csv, contains('""引用""'));
      expect(csv, endsWith('\n'));
      expect(UafCsv.parse(csv), document);
      expect(UafCsv.parseUtf8(UafCsv.serializeToUtf8(document)), document);
      final bytes = UafCsv.serializeToUtf8(document);
      expect(bytes.sublist(0, 3), isNot(equals(<int>[0xef, 0xbb, 0xbf])));
    });

    test('accepts a BOM when reading and rejects malformed UTF-8', () {
      final csv = UafCsv.serialize(sampleDocument());
      expect(UafCsv.parse('\uFEFF$csv'), sampleDocument());
      expect(
        () => UafCsv.parseUtf8(const <int>[0xff, 0xfe]),
        throwsUaf(UafErrorCode.invalidCsv),
      );
    });

    test('accepts no terminator or one LF/CRLF record terminator', () {
      const withoutTerminator = 'subject,date,content,tags\n数学,2026-05-19,正文,';
      final expected = UafDocument(<UafAssignment>[
        UafAssignment(subject: '数学', date: '2026-05-19', content: '正文'),
      ]);

      expect(UafCsv.parse(withoutTerminator), expected);
      expect(UafCsv.parse('$withoutTerminator\n'), expected);
      expect(
        UafCsv.parse('${withoutTerminator.replaceAll('\n', '\r\n')}\r\n'),
        expected,
      );
    });

    test('does not trim input or ignore blank and whitespace records', () {
      const row = '数学,2026-05-19,正文,';
      final invalidInputs = <String>[
        ' ${UafConstants.csvHeader}\n$row\n',
        '${UafConstants.csvHeader} \n$row\n',
        '${UafConstants.csvHeader}\n\n$row\n',
        '${UafConstants.csvHeader}\n$row\n\n',
        '${UafConstants.csvHeader}\n$row\n   ',
        '${UafConstants.csvHeader}\r$row\r',
      ];

      for (final csv in invalidInputs) {
        expect(
          () => UafCsv.parse(csv),
          throwsUaf(UafErrorCode.invalidCsv),
          reason: csv.replaceAll('\n', r'\n'),
        );
      }
    });

    test('rejects malformed rows and headers', () {
      expect(
        () => UafCsv.parse('subject,date,content,tags\n数学,2026-05-19,"未结束,必做'),
        throwsUaf(UafErrorCode.invalidCsv),
      );
      expect(
        () => UafCsv.parse('date,subject,content,tags\n2026-05-19,数学,正文,'),
        throwsUaf(UafErrorCode.invalidCsv),
      );
      expect(
        () => UafCsv.parse('"subject",date,content,tags\n数学,2026-05-19,正文,'),
        throwsUaf(UafErrorCode.invalidCsv),
      );
      expect(
        () => UafCsv.parse('subject,date,content,tags\n数学,2026-05-19,正文,标签,多余'),
        throwsUaf(UafErrorCode.invalidCsv),
      );
    });

    test('parses the repository golden payload', () {
      final bytes = repositoryPath('examples/uaf_payload.sample.csv');
      final csv = UafCsv.parseUtf8(File(bytes).readAsBytesSync());
      expect(csv.length, 3);
      expect(csv.first.subject, '数学');
      expect(csv.last.tags, isEmpty);
    });
  });
}
