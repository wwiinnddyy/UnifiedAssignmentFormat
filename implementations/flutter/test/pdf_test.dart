import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:unified_assignment_format/unified_assignment_format.dart';

import 'test_data.dart';

const bool _hasIo = bool.fromEnvironment('dart.library.io');

void main() {
  group('UAF PDF', () {
    test('creates, validates, and restores a multi-page document', () {
      final assignments = List<UafAssignment>.generate(
        5,
        (int index) => UafAssignment(
          subject: '科目$index',
          date: '2026-05-19',
          content: '第 $index 项作业',
          tags: const <String>['必做'],
        ),
      );
      final document = UafDocument(assignments);
      final bytes = UafPdf.create(document);
      final pdfText = latin1.decode(bytes);

      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(pdfText, contains('/FontFile2'));
      expect(pdfText, contains('/ToUnicode'));
      expect(pdfText, contains('/BaseFont /UAFNSC+NotoSansSC-Regular'));
      expect(pdfText, isNot(contains('/STSong-Light')));
      expect(bytes.length, lessThan(500000));
      expect(UafPdf.extractPayload(bytes), document);

      final validation = UafPdf.validate(bytes);
      expect(validation.valid, isTrue);
      expect(validation.pageCount, 2);
      expect(validation.payload, document);
      expect(validation.errors, isEmpty);
    });

    test('extracts the shared TypeScript-generated PDF', () {
      if (!_hasIo) return;
      final expected = UafCsv.parseUtf8(
        File(
          repositoryPath('examples/uaf_payload.sample.csv'),
        ).readAsBytesSync(),
      );
      final bytes = File(
        repositoryPath('examples/sample-homework.pdf'),
      ).readAsBytesSync();

      expect(UafPdf.extractPayload(bytes), expected);
      expect(UafPdf.validate(bytes).valid, isTrue);
    });

    test('extracts an in-memory xref and object-stream carrier', () {
      final expected = sampleDocument();
      final bytes = _objectStreamPdf(UafCsv.serializeToUtf8(expected));

      expect(UafPdf.extractPayload(bytes), expected);
      expect(UafPdf.validate(bytes).pageCount, 1);
    });

    test(
      'treats a valid PDF without the exact attachment name as ordinary',
      () {
        final ordinary = _plainPdf();
        expect(UafPdf.tryExtractPayloadCsv(ordinary), isNull);
        expect(
          () => UafPdf.extractPayloadCsv(ordinary),
          throwsUaf(UafErrorCode.noPayload),
        );

        final renamed = Uint8List.fromList(UafPdf.create(sampleDocument()));
        expect(
          _replaceAll(
            renamed,
            ascii.encode('uaf_payload.csv'),
            ascii.encode('UAF_PAYLOAD.CSV'),
          ),
          greaterThan(0),
        );
        expect(
          _replaceAll(
            renamed,
            ascii.encode(_utf16Hex('uaf_payload.csv')),
            ascii.encode(_utf16Hex('UAF_PAYLOAD.CSV')),
          ),
          greaterThan(0),
        );
        expect(UafPdf.tryExtractPayloadCsv(renamed), isNull);
      },
    );

    test(
      'does not combine an unrelated filename with an orphan CSV stream',
      () {
        final ordinary = _attachmentPdf(
          treeName: 'notes.csv',
          fileSpecName: 'notes.csv',
          attachment: Uint8List.fromList(utf8.encode('not a UAF payload')),
          extraObjects: <Uint8List>[
            Uint8List.fromList(ascii.encode('(uaf_payload.csv)')),
            _streamBody(UafCsv.serializeToUtf8(sampleDocument())),
          ],
        );

        expect(UafPdf.tryExtractPayloadCsv(ordinary), isNull);
        expect(
          () => UafPdf.extractPayloadCsv(ordinary),
          throwsUaf(UafErrorCode.noPayload),
        );
      },
    );

    test('requires both the name-tree key and FileSpec name to match', () {
      final payload = UafCsv.serializeToUtf8(sampleDocument());
      final matchingTreeOnly = _attachmentPdf(
        treeName: 'uaf_payload.csv',
        fileSpecName: 'uaf_payload.csv',
        fileSpecUnicodeName: 'other_payload.csv',
        attachment: payload,
      );
      final matchingFileSpecOnly = _attachmentPdf(
        treeName: 'other_payload.csv',
        fileSpecName: 'uaf_payload.csv',
        attachment: payload,
      );

      expect(UafPdf.tryExtractPayloadCsv(matchingTreeOnly), isNull);
      expect(UafPdf.tryExtractPayloadCsv(matchingFileSpecOnly), isNull);
    });

    test('does not accept FileSpec F when the required UF is missing', () {
      final missingUnicodeName = _attachmentPdf(
        treeName: 'uaf_payload.csv',
        fileSpecName: 'uaf_payload.csv',
        includeFileSpecUnicodeName: false,
        attachment: UafCsv.serializeToUtf8(sampleDocument()),
      );

      expect(UafPdf.tryExtractPayloadCsv(missingUnicodeName), isNull);
      expect(
        () => UafPdf.extractPayloadCsv(missingUnicodeName),
        throwsUaf(UafErrorCode.noPayload),
      );
    });

    test('reports an exact attachment whose CSV is invalid', () {
      final invalidCsv = _attachmentPdf(
        attachment: Uint8List.fromList(
          utf8.encode('subject,date,content,tags\nonly,three,columns\n'),
        ),
      );

      expect(
        () => UafPdf.tryExtractPayloadCsv(invalidCsv),
        throwsUaf(UafErrorCode.invalidCsv),
      );
      expect(UafPdf.validate(invalidCsv).valid, isFalse);
      expect(
        UafPdf.validate(invalidCsv).errors.single,
        contains('expected 4 columns'),
      );

      final invalidPayload = _attachmentPdf(
        attachment: Uint8List.fromList(
          utf8.encode('subject,date,content,tags\n,2026-05-19,内容,\n'),
        ),
      );
      expect(
        () => UafPdf.tryExtractPayloadCsv(invalidPayload),
        throwsUaf(UafErrorCode.invalidCsv),
      );
    });

    test('only inflates streams that explicitly declare FlateDecode', () {
      final compressed = const ZLibEncoder().encodeBytes(
        UafCsv.serializeToUtf8(sampleDocument()),
      );
      final missingFilter = _attachmentPdf(attachment: compressed);

      expect(
        () => UafPdf.tryExtractPayloadCsv(missingFilter),
        throwsUaf(UafErrorCode.invalidCsv),
      );
    });

    test('rejects a FlateDecode payload that exceeds the ratio limit', () {
      final repetitive = List<String>.filled(500000, 'A').join();
      final uncompressed = Uint8List.fromList(
        utf8.encode(
          'subject,date,content,tags\n'
          '压缩测试,2026-05-19,"$repetitive",\n',
        ),
      );
      final compressed = const ZLibEncoder().encodeBytes(uncompressed);
      expect(uncompressed.length, greaterThan(compressed.length * 200));

      final bomb = _attachmentPdf(
        attachment: compressed,
        filter: 'FlateDecode',
      );
      expect(
        () => UafPdf.tryExtractPayloadCsv(bomb),
        throwsUaf(UafErrorCode.corruptPdf),
      );
    });

    test('rejects a stream whose declared input exceeds the hard limit', () {
      final oversized = _attachmentPdf(
        attachment: Uint8List(1),
        declaredLength: 9000000,
      );

      expect(
        () => UafPdf.tryExtractPayloadCsv(oversized),
        throwsUaf(UafErrorCode.corruptPdf),
      );
    });

    test('uses only the current Catalog page tree for page count', () {
      final bytes = _attachmentPdf(
        attachment: UafCsv.serializeToUtf8(sampleDocument()),
        extraObjects: <Uint8List>[
          Uint8List.fromList(
            ascii.encode('<< /Type /Pages /Count 999 /Kids [] >>'),
          ),
          Uint8List.fromList(ascii.encode('<< /Type /Catalog /Pages 6 0 R >>')),
        ],
      );

      final validation = UafPdf.validate(bytes);
      expect(validation.valid, isTrue);
      expect(validation.pageCount, 1);
    });

    test('does not restore a payload from an obsolete incremental root', () {
      final original = _attachmentPdf(
        attachment: UafCsv.serializeToUtf8(sampleDocument()),
      );
      final updated = _appendRootWithoutPayload(original);

      expect(UafPdf.tryExtractPayloadCsv(updated), isNull);
      final validation = UafPdf.validate(updated);
      expect(validation.valid, isFalse);
      expect(validation.pageCount, 1);
    });

    test('long assignment content is never omitted from content streams', () {
      final content = List<String>.generate(
        1600,
        (int index) => String.fromCharCode(0x41 + index % 26),
      ).join();
      final tags = List<String>.generate(8, (int index) => '标签$index');
      final document = UafDocument(<UafAssignment>[
        UafAssignment(
          subject: '长文',
          date: '2026-05-19',
          content: content,
          tags: tags,
        ),
      ]);

      final bytes = UafPdf.create(document);
      final allShown = _shownText(bytes).toList();
      final shown = allShown.where(
        (String value) => RegExp(r'^[A-Z]+$').hasMatch(value),
      );

      expect(allShown, containsAll(tags));
      expect(allShown.any((String value) => value.contains('续')), isTrue);
      expect(shown.join(), content);
      expect(UafPdf.extractPayload(bytes), document);
    });

    test('rejects characters missing from the bundled PDF font', () {
      const unsupported = <(String, String)>[
        ('∑', 'U+2211'),
        ('π', 'U+03C0'),
        ('😀', 'U+1F600'),
        ('العربية', 'U+0627'),
      ];

      for (final testCase in unsupported) {
        final document = UafDocument(<UafAssignment>[
          UafAssignment(
            subject: '字符测试',
            date: '2026-05-19',
            content: '不支持字符：${testCase.$1}',
          ),
        ]);

        expect(
          () => UafPdf.create(document),
          throwsA(
            isA<UafException>()
                .having(
                  (UafException error) => error.code,
                  'code',
                  UafErrorCode.invalidPayload,
                )
                .having(
                  (UafException error) => error.message,
                  'message',
                  contains(testCase.$2),
                ),
          ),
        );
      }
    });

    test('renders common Chinese through the embedded ToUnicode map', () {
      final document = UafDocument(<UafAssignment>[
        UafAssignment(
          subject: '语文',
          date: '2026-05-19',
          content: '背诵《静夜思》，完成生字练习。',
          tags: const <String>['必做', '朗读'],
        ),
      ]);

      final bytes = UafPdf.create(document);
      final shown = _shownText(bytes).toList(growable: false);
      expect(shown, containsAll(<String>['语文', '必做', '朗读']));
      expect(shown.join(), contains('背诵《静夜思》，完成生字练习。'));
      expect(UafPdf.extractPayload(bytes), document);
    });

    test('reports truncated or structurally invalid PDFs', () {
      final invalid = Uint8List.fromList(ascii.encode('%PDF-1.7\ntruncated'));
      expect(
        () => UafPdf.tryExtractPayloadCsv(invalid),
        throwsUaf(UafErrorCode.corruptPdf),
      );
      final validation = UafPdf.validate(invalid);
      expect(validation.valid, isFalse);
      expect(validation.pageCount, 0);
    });
  });
}

Uint8List _attachmentPdf({
  String treeName = 'uaf_payload.csv',
  String fileSpecName = 'uaf_payload.csv',
  String? fileSpecUnicodeName,
  bool includeFileSpecUnicodeName = true,
  required Uint8List attachment,
  String? filter,
  int? declaredLength,
  List<Uint8List> extraObjects = const <Uint8List>[],
}) {
  final objects = <Uint8List>[
    Uint8List.fromList(
      ascii.encode(
        '<< /Type /Catalog /Pages 2 0 R '
        '/Names << /EmbeddedFiles << /Names '
        '[($treeName) 4 0 R] >> >> >>',
      ),
    ),
    Uint8List.fromList(
      ascii.encode('<< /Type /Pages /Count 1 /Kids [3 0 R] >>'),
    ),
    Uint8List.fromList(
      ascii.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] >>'),
    ),
    Uint8List.fromList(
      ascii.encode(
        '<< /Type /Filespec /F ($fileSpecName) '
        '${includeFileSpecUnicodeName ? '/UF (${fileSpecUnicodeName ?? fileSpecName}) ' : ''}'
        '/EF << /F 5 0 R >> >>',
      ),
    ),
    _streamBody(attachment, filter: filter, declaredLength: declaredLength),
    ...extraObjects,
  ];
  return _pdfFromObjects(objects);
}

Uint8List _streamBody(Uint8List bytes, {String? filter, int? declaredLength}) {
  final output = BytesBuilder(copy: false)
    ..add(
      ascii.encode(
        '<< /Length ${declaredLength ?? bytes.length}'
        '${filter == null ? '' : ' /Filter /$filter'} >>\nstream\n',
      ),
    )
    ..add(bytes)
    ..add(ascii.encode('\nendstream'));
  return output.takeBytes();
}

Uint8List _pdfFromObjects(List<Uint8List> objects) {
  final output = BytesBuilder(copy: false)..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(output.length);
    output
      ..add(ascii.encode('${index + 1} 0 obj\n'))
      ..add(objects[index])
      ..add(ascii.encode('\nendobj\n'));
  }
  final xref = output.length;
  output
    ..add(ascii.encode('xref\n0 ${objects.length + 1}\n'))
    ..add(ascii.encode('0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    output.add(
      ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
    );
  }
  output.add(
    ascii.encode(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    ),
  );
  return output.takeBytes();
}

Uint8List _appendRootWithoutPayload(Uint8List original) {
  final originalText = latin1.decode(original);
  final previousMatch = RegExp(
    r'startxref\s+(\d+)\s+%%EOF\s*$',
  ).firstMatch(originalText);
  expect(previousMatch, isNotNull);
  final previousXref = int.parse(previousMatch!.group(1)!);

  final output = BytesBuilder(copy: false)
    ..add(original)
    ..add(ascii.encode('\n'));
  final catalogOffset = output.length;
  output.add(
    ascii.encode('6 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'),
  );
  final xrefOffset = output.length;
  output.add(
    ascii.encode(
      'xref\n6 1\n'
      '${catalogOffset.toString().padLeft(10, '0')} 00000 n \n'
      'trailer\n<< /Size 7 /Root 6 0 R /Prev $previousXref >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    ),
  );
  return output.takeBytes();
}

Uint8List _objectStreamPdf(Uint8List csvBytes) {
  final compressedBodies = <Uint8List>[
    Uint8List.fromList(
      ascii.encode(
        '<< /Type /Catalog /Pages 2 0 R '
        '/Names << /EmbeddedFiles << /Names '
        '[(uaf_payload.csv) 4 0 R] >> >> >>',
      ),
    ),
    Uint8List.fromList(
      ascii.encode('<< /Type /Pages /Count 1 /Kids [3 0 R] >>'),
    ),
    Uint8List.fromList(
      ascii.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] >>'),
    ),
    Uint8List.fromList(
      ascii.encode(
        '<< /Type /Filespec /F (uaf_payload.csv) '
        '/UF (uaf_payload.csv) '
        '/EF << /F 5 0 R >> >>',
      ),
    ),
  ];
  final body = BytesBuilder(copy: false);
  final bodyOffsets = <int>[];
  for (final object in compressedBodies) {
    bodyOffsets.add(body.length);
    body
      ..add(object)
      ..addByte(0x20);
  }
  final header = ascii.encode(
    <String>[
      for (var index = 0; index < bodyOffsets.length; index++)
        '${index + 1} ${bodyOffsets[index]}',
    ].join(' '),
  );
  final decodedObjectStream = BytesBuilder(copy: false)
    ..add(header)
    ..addByte(0x20)
    ..add(body.takeBytes());
  final first = header.length + 1;
  final compressedObjectStream = const ZLibEncoder().encodeBytes(
    decodedObjectStream.takeBytes(),
  );

  final output = BytesBuilder(copy: false)..add(ascii.encode('%PDF-1.7\n'));
  final embeddedOffset = output.length;
  output
    ..add(ascii.encode('5 0 obj\n'))
    ..add(_streamBody(csvBytes))
    ..add(ascii.encode('\nendobj\n'));
  final objectStreamOffset = output.length;
  output
    ..add(
      ascii.encode(
        '7 0 obj\n<< /Type /ObjStm /N 4 /First $first '
        '/Filter /FlateDecode /Length ${compressedObjectStream.length} >>\n'
        'stream\n',
      ),
    )
    ..add(compressedObjectStream)
    ..add(ascii.encode('\nendstream\nendobj\n'));
  final xrefOffset = output.length;

  final xrefBytes = BytesBuilder(copy: false);
  void addXref(int type, int field2, int field3) {
    xrefBytes
      ..addByte(type)
      ..add(_bigEndian(field2, 4))
      ..add(_bigEndian(field3, 2));
  }

  addXref(0, 0, 65535);
  for (var index = 0; index < 4; index++) {
    addXref(2, 7, index);
  }
  addXref(1, embeddedOffset, 0);
  addXref(0, 0, 0);
  addXref(1, objectStreamOffset, 0);
  addXref(1, xrefOffset, 0);
  final compressedXref = const ZLibEncoder().encodeBytes(xrefBytes.takeBytes());

  output
    ..add(
      ascii.encode(
        '8 0 obj\n<< /Type /XRef /Size 9 /Root 1 0 R '
        '/W [1 4 2] /Index [0 9] /Filter /FlateDecode '
        '/Length ${compressedXref.length} >>\nstream\n',
      ),
    )
    ..add(compressedXref)
    ..add(ascii.encode('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n'));
  return output.takeBytes();
}

Uint8List _bigEndian(int value, int width) {
  final bytes = Uint8List(width);
  for (var index = width - 1; index >= 0; index--) {
    bytes[index] = value & 0xff;
    value ~/= 256;
  }
  return bytes;
}

Iterable<String> _shownText(Uint8List bytes) sync* {
  final text = latin1.decode(bytes);
  final toUnicode = <int, String>{};
  for (final section in RegExp(
    r'\d+\s+beginbfchar([\s\S]*?)endbfchar',
  ).allMatches(text)) {
    for (final mapping in RegExp(
      r'<([0-9A-F]{4})>\s*<([0-9A-F]{4,8})>',
    ).allMatches(section.group(1)!)) {
      final unicodeHex = mapping.group(2)!;
      final codeUnits = <int>[
        for (var index = 0; index < unicodeHex.length; index += 4)
          int.parse(unicodeHex.substring(index, index + 4), radix: 16),
      ];
      toUnicode[int.parse(mapping.group(1)!, radix: 16)] = String.fromCharCodes(
        codeUnits,
      );
    }
  }
  expect(toUnicode, isNotEmpty);

  for (final match in RegExp(r'<([0-9A-F]+)> Tj').allMatches(text)) {
    final hex = match.group(1)!;
    expect(hex.length % 4, 0);
    final decoded = StringBuffer();
    for (var index = 0; index < hex.length; index += 4) {
      final cid = int.parse(hex.substring(index, index + 4), radix: 16);
      decoded.write(toUnicode[cid] ?? '\uFFFD');
    }
    yield decoded.toString();
  }
}

Uint8List _plainPdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Contents 4 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
  ];
  final output = BytesBuilder(copy: false)..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(output.length);
    output.add(ascii.encode('${index + 1} 0 obj\n${objects[index]}\nendobj\n'));
  }
  final xref = output.length;
  output.add(ascii.encode('xref\n0 ${objects.length + 1}\n'));
  output.add(ascii.encode('0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    output.add(
      ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
    );
  }
  output.add(
    ascii.encode(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    ),
  );
  return output.takeBytes();
}

String _utf16Hex(String value) => value.codeUnits
    .map((int codeUnit) => codeUnit.toRadixString(16).padLeft(4, '0'))
    .join()
    .toUpperCase();

int _replaceAll(Uint8List bytes, List<int> before, List<int> after) {
  expect(after.length, before.length);
  var replacements = 0;
  for (var index = 0; index <= bytes.length - before.length; index++) {
    var matches = true;
    for (var offset = 0; offset < before.length; offset++) {
      if (bytes[index + offset] != before[offset]) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    bytes.setRange(index, index + after.length, after);
    replacements++;
    index += after.length - 1;
  }
  return replacements;
}
