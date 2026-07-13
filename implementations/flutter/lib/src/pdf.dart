import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart' show TtfParser;
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/ttf_writer.dart' show TtfWriter;

import 'constants.dart';
import 'csv.dart';
import 'errors.dart';
import 'font_data.dart';
import 'model.dart';

/// The result of checking whether a PDF is a structurally valid UAF carrier.
final class UafPdfValidationResult {
  /// Creates an immutable validation result.
  UafPdfValidationResult({
    required this.valid,
    required this.pageCount,
    required this.payload,
    required Iterable<String> errors,
  }) : errors = List<String>.unmodifiable(errors);

  /// Whether the PDF has at least one page and a valid UAF payload.
  final bool valid;

  /// The page count reported by the PDF page tree, or zero when unavailable.
  final int pageCount;

  /// The restored payload when validation succeeds.
  final UafDocument? payload;

  /// Human-readable validation failures.
  final List<String> errors;
}

/// Pure-Dart UAF PDF creation, extraction, and validation.
///
/// PDF pages are assembled directly from PDF objects and content streams. A
/// per-document Noto Sans SC TrueType subset is embedded with a ToUnicode map,
/// keeping Chinese text self-contained, searchable, and selectable.
abstract final class UafPdf {
  static const double _pageWidth = 595.28;
  static const double _pageHeight = 841.89;
  static const double _cardMargin = 40;
  static const double _cardGap = 14;
  static const double _cardWidth =
      (_pageWidth - _cardMargin * 2 - _cardGap) / 2;
  static const double _cardMaxHeight = 340;
  static const double _bodyWidth = _cardWidth - 48;
  static const double _bodyMaxHeight = 150;
  static const double _minimumBodyFontSize = 14;
  static const double _minimumBodyLineHeight = 21;

  static final Uint8List _pdfHeader = Uint8List.fromList(ascii.encode('%PDF-'));
  static final Uint8List _startXrefMarker = Uint8List.fromList(
    ascii.encode('startxref'),
  );
  static final Uint8List _eofMarker = Uint8List.fromList(ascii.encode('%%EOF'));

  /// Creates a one-or-more-page A4 PDF containing every assignment and an
  /// embedded, uncompressed UTF-8 `uaf_payload.csv` attachment.
  static Uint8List create(UafDocument payload) {
    final csvBytes = UafCsv.serializeToUtf8(payload);
    final font = _EmbeddedFont.build(payload);
    final fragments = _expandAssignments(payload, font);
    final pageGroups = <List<_AssignmentFragment>>[];
    for (var index = 0; index < fragments.length; index += 4) {
      pageGroups.add(
        fragments.sublist(index, math.min(index + 4, fragments.length)),
      );
    }

    final fontObject = 3 + pageGroups.length * 2;
    final cidObject = fontObject + 1;
    final embeddedObject = fontObject + 2;
    final fileSpecObject = fontObject + 3;
    final descriptorObject = fontObject + 4;
    final fontFileObject = fontObject + 5;
    final cidToGidObject = fontObject + 6;
    final toUnicodeObject = fontObject + 7;
    final kids = <String>[
      for (var index = 0; index < pageGroups.length; index++)
        '${3 + index * 2} 0 R',
    ].join(' ');

    final objects = <Uint8List>[
      _object(
        '<< /Type /Catalog /Pages 2 0 R '
        '/Names << /EmbeddedFiles << /Names '
        '[(uaf_payload.csv) $fileSpecObject 0 R] >> >> '
        '/AF [$fileSpecObject 0 R] >>',
      ),
      _object('<< /Type /Pages /Count ${pageGroups.length} /Kids [$kids] >>'),
    ];

    for (var index = 0; index < pageGroups.length; index++) {
      final contentBytes = Uint8List.fromList(
        ascii.encode(_renderGridPage(pageGroups[index], font)),
      );
      final contentObject = 4 + index * 2;
      objects
        ..add(
          _object(
            '<< /Type /Page /Parent 2 0 R '
            '/MediaBox [0 0 595.28 841.89] '
            '/Resources << /Font << /F1 $fontObject 0 R >> >> '
            '/Contents $contentObject 0 R >>',
          ),
        )
        ..add(
          _streamObject('<< /Length ${contentBytes.length} >>', contentBytes),
        );
    }

    final fileNameHex = _toUtf16Hex(
      UafConstants.payloadFileName,
      includeBom: true,
    );
    objects
      ..add(
        _object(
          '<< /Type /Font /Subtype /Type0 '
          '/BaseFont /UAFNSC+NotoSansSC-Regular '
          '/Encoding /Identity-H /DescendantFonts [$cidObject 0 R] '
          '/ToUnicode $toUnicodeObject 0 R >>',
        ),
      )
      ..add(
        _object(
          '<< /Type /Font /Subtype /CIDFontType2 '
          '/BaseFont /UAFNSC+NotoSansSC-Regular '
          '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
          '/Supplement 0 >> /DW 1000 /W ${font.widthsArray} '
          '/CIDToGIDMap $cidToGidObject 0 R '
          '/FontDescriptor $descriptorObject 0 R >>',
        ),
      )
      ..add(
        _streamObject(
          '<< /Type /EmbeddedFile /Subtype /text#2Fcsv '
          '/Params << /Size ${csvBytes.length} >> '
          '/Length ${csvBytes.length} >>',
          csvBytes,
        ),
      )
      ..add(
        _object(
          '<< /Type /Filespec /F (uaf_payload.csv) '
          '/UF <$fileNameHex> '
          '/Desc (UAF v1.0 multi-assignment payload) '
          '/AFRelationship /Data '
          '/EF << /F $embeddedObject 0 R /UF $embeddedObject 0 R >> >>',
        ),
      )
      ..add(
        _object(
          '<< /Type /FontDescriptor '
          '/FontName /UAFNSC+NotoSansSC-Regular /Flags 4 '
          '/FontBBox [-1000 -1000 2000 2000] /ItalicAngle 0 '
          '/Ascent 880 /Descent -120 /CapHeight 700 /StemV 80 '
          '/FontFile2 $fontFileObject 0 R >>',
        ),
      )
      ..add(
        _streamObject(
          '<< /Length ${font.compressedFont.length} '
          '/Filter /FlateDecode /Length1 ${font.subsetFont.length} >>',
          font.compressedFont,
        ),
      )
      ..add(
        _streamObject(
          '<< /Length ${font.compressedCidToGid.length} '
          '/Filter /FlateDecode >>',
          font.compressedCidToGid,
        ),
      )
      ..add(
        _streamObject(
          '<< /Length ${font.toUnicodeBytes.length} >>',
          font.toUnicodeBytes,
        ),
      );

    return _writePdf(objects);
  }

  /// Extracts and parses the embedded UAF payload.
  static UafDocument extractPayload(Uint8List pdfBytes) {
    return UafCsv.parse(extractPayloadCsv(pdfBytes));
  }

  /// Extracts the embedded UAF CSV, throwing [UafErrorCode.noPayload] when the
  /// PDF is valid but has no case-sensitive `uaf_payload.csv` attachment.
  static String extractPayloadCsv(Uint8List pdfBytes) {
    final csv = tryExtractPayloadCsv(pdfBytes);
    if (csv == null) {
      throw UafException(
        UafErrorCode.noPayload,
        'Embedded file "${UafConstants.payloadFileName}" not found.',
      );
    }
    return csv;
  }

  /// Returns the valid embedded UAF CSV, or `null` for an ordinary PDF.
  ///
  /// A malformed carrier is not an ordinary PDF and throws
  /// [UafErrorCode.corruptPdf]. Both traditional xref tables and xref/object
  /// streams are accepted. Flate-compressed streams produced by the C# and
  /// TypeScript implementations are inspected without a PDF dependency.
  static String? tryExtractPayloadCsv(Uint8List pdfBytes) {
    return _inspectPdf(pdfBytes).csv;
  }

  /// Validates PDF structure, page count, attachment name, and CSV payload.
  ///
  /// Unlike the extraction methods, validation reports failures in the result
  /// instead of throwing.
  static UafPdfValidationResult validate(Uint8List pdfBytes) {
    try {
      final inspection = _inspectPdf(pdfBytes);
      if (inspection.csv == null) {
        return UafPdfValidationResult(
          valid: false,
          pageCount: inspection.pageCount,
          payload: null,
          errors: <String>[
            'Embedded file "${UafConstants.payloadFileName}" not found.',
          ],
        );
      }

      try {
        final payload = UafCsv.parse(inspection.csv!);
        return UafPdfValidationResult(
          valid: true,
          pageCount: inspection.pageCount,
          payload: payload,
          errors: const <String>[],
        );
      } on UafException catch (error) {
        return UafPdfValidationResult(
          valid: false,
          pageCount: inspection.pageCount,
          payload: null,
          errors: <String>[error.message],
        );
      }
    } on UafException catch (error) {
      return UafPdfValidationResult(
        valid: false,
        pageCount: 0,
        payload: null,
        errors: <String>[error.message],
      );
    } on Object catch (error) {
      return UafPdfValidationResult(
        valid: false,
        pageCount: 0,
        payload: null,
        errors: <String>['Failed to load PDF: $error'],
      );
    }
  }

  static _PdfInspection _inspectPdf(Uint8List pdfBytes) {
    try {
      return _PdfReader(pdfBytes).inspect();
    } on UafException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw UafException(
        UafErrorCode.corruptPdf,
        'Failed to parse PDF structure.',
        error,
        stackTrace,
      );
    }
  }

  static Uint8List _writePdf(List<Uint8List> objects) {
    final output = BytesBuilder(copy: false);
    output
      ..add(ascii.encode('%PDF-1.7\n%'))
      ..add(const <int>[0xe2, 0xe3, 0xcf, 0xd3])
      ..addByte(0x0a);

    final offsets = List<int>.filled(objects.length + 1, 0);
    for (var index = 0; index < objects.length; index++) {
      offsets[index + 1] = output.length;
      output
        ..add(ascii.encode('${index + 1} 0 obj\n'))
        ..add(objects[index])
        ..add(ascii.encode('\nendobj\n'));
    }

    final xrefOffset = output.length;
    output
      ..add(ascii.encode('xref\n0 ${objects.length + 1}\n'))
      ..add(ascii.encode('0000000000 65535 f \n'));
    for (var index = 1; index < offsets.length; index++) {
      output.add(
        ascii.encode(
          '${offsets[index].toString().padLeft(10, '0')} 00000 n \n',
        ),
      );
    }
    output.add(
      ascii.encode(
        'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF\n',
      ),
    );
    return output.takeBytes();
  }

  static List<_AssignmentFragment> _expandAssignments(
    UafDocument document,
    _EmbeddedFont font,
  ) {
    final fragments = <_AssignmentFragment>[];
    for (final assignment in document) {
      final wrapped = _wrapContent(
        assignment.content,
        _bodyWidth,
        _minimumBodyFontSize,
        font,
      );
      final linesPerCard = (_bodyMaxHeight / _minimumBodyLineHeight).floor();
      final tagGroups = _partitionTags(assignment.tags, font);
      var contentFragmentIndex = 0;
      for (var index = 0; index < wrapped.length; index += linesPerCard) {
        final end = math.min(index + linesPerCard, wrapped.length);
        final isFinal = end == wrapped.length;
        fragments.add(
          _AssignmentFragment(
            subject:
                '${assignment.subject}${contentFragmentIndex > 0 ? '（续）' : ''}',
            date: assignment.date,
            content: wrapped.sublist(index, end).join('\n'),
            tags: isFinal && tagGroups.isNotEmpty
                ? tagGroups.first
                : const <String>[],
          ),
        );
        contentFragmentIndex++;
      }
      for (final tags in tagGroups.skip(1)) {
        fragments.add(
          _AssignmentFragment(
            subject: '${assignment.subject}（续）',
            date: assignment.date,
            content: '',
            tags: tags,
          ),
        );
      }
    }
    return fragments;
  }

  static List<List<String>> _partitionTags(
    List<String> tags,
    _EmbeddedFont font,
  ) {
    if (tags.isEmpty) return const <List<String>>[];

    final groups = <List<String>>[];
    var current = <String>[];
    var row = 1;
    var used = 0.0;
    for (final tag in tags) {
      final width = math.min(font.textWidth(tag, 11) + 20, _bodyWidth);
      if (used > 0 && used + 8 + width > _bodyWidth) {
        if (row == 2) {
          groups.add(List<String>.unmodifiable(current));
          current = <String>[];
          row = 1;
        } else {
          row++;
        }
        used = 0;
      }
      current.add(tag);
      used += width + (used == 0 ? 0 : 8);
    }
    groups.add(List<String>.unmodifiable(current));
    return List<List<String>>.unmodifiable(groups);
  }

  static String _renderGridPage(
    List<_AssignmentFragment> assignments,
    _EmbeddedFont font,
  ) {
    final builder = StringBuffer()
      ..writeln('q 0.973 0.980 0.988 rg 0 0 595.28 841.89 re f Q');

    final layouts = assignments
        .map((assignment) => _layoutCard(assignment, font))
        .toList(growable: false);
    final firstRowHeight = layouts
        .take(math.min(2, layouts.length))
        .fold<double>(
          0,
          (double value, _CardLayout layout) => math.max(value, layout.height),
        );
    final secondRowTop = _pageHeight - _cardMargin - firstRowHeight - _cardGap;

    for (var index = 0; index < assignments.length; index++) {
      final assignment = assignments[index];
      final cardLayout = layouts[index];
      final column = index % 2;
      final row = index ~/ 2;
      final x = _cardMargin + column * (_cardWidth + _cardGap);
      final rowTop = row == 0 ? _pageHeight - _cardMargin : secondRowTop;
      final y = rowTop - cardLayout.height;
      builder
        ..writeln('q 0.80 0.84 0.89 rg')
        ..writeln(
          _roundedRectPath(x + 2, y - 2, _cardWidth, cardLayout.height, 16),
        )
        ..writeln('f Q q 1 1 1 rg')
        ..writeln(_roundedRectPath(x, y, _cardWidth, cardLayout.height, 16))
        ..writeln('f Q q 0.886 0.910 0.941 RG 1 w')
        ..writeln(_roundedRectPath(x, y, _cardWidth, cardLayout.height, 16))
        ..writeln('S Q');

      final cardTop = y + cardLayout.height;
      const subjectHeight = 30.0;
      const dateHeight = 26.0;
      final dateText = _formatDateZh(assignment.date);
      final dateWidth = math.min(
        font.textWidth(dateText, 12) + 24,
        _bodyWidth * 0.62,
      );
      final subjectMaxWidth = math.max(38.0, _bodyWidth - dateWidth - 12);
      final subjectWidth = math.min(
        font.textWidth(assignment.subject, 14) + 32,
        subjectMaxWidth,
      );
      final subjectX = x + 24;
      final subjectY = cardTop - 24 - subjectHeight;
      final dateX = x + _cardWidth - 24 - dateWidth;
      final dateY = cardTop - 24 - dateHeight - 2;
      builder
        ..writeln('q 0.145 0.388 0.922 rg')
        ..writeln(
          _roundedRectPath(
            subjectX,
            subjectY,
            subjectWidth,
            subjectHeight,
            subjectHeight / 2,
          ),
        )
        ..writeln('f Q q 0.945 0.961 0.976 rg')
        ..writeln(
          _roundedRectPath(dateX, dateY, dateWidth, dateHeight, dateHeight / 2),
        )
        ..writeln('f Q');

      _appendText(
        builder,
        _ellipsizeSubject(assignment.subject, subjectWidth - 32, 14, font),
        subjectX + 16,
        subjectY + 8,
        14,
        '#FFFFFF',
        font,
      );
      _appendText(
        builder,
        _ellipsizeToWidth(dateText, dateWidth - 24, 12, font),
        dateX + 12,
        dateY + 7,
        12,
        '#334155',
        font,
      );

      final dividerY = subjectY - 16;
      builder.writeln(
        'q 0.886 0.910 0.941 RG 1 w '
        '${_formatNumber(x + 24)} ${_formatNumber(dividerY)} m '
        '${_formatNumber(x + _cardWidth - 24)} ${_formatNumber(dividerY)} l '
        'S Q',
      );

      var lineY = dividerY - 20 - cardLayout.content.fontSize;
      for (final line in cardLayout.content.lines) {
        _appendText(
          builder,
          line,
          x + 24,
          lineY,
          cardLayout.content.fontSize,
          '#0F172A',
          font,
        );
        lineY -= cardLayout.content.lineHeight;
      }

      var tagX = x + 24;
      var tagRow = 0;
      for (final tag in assignment.tags) {
        final tagWidth = math.min(font.textWidth(tag, 11) + 20, _bodyWidth);
        if (tagX > x + 24 && tagX + tagWidth > x + _cardWidth - 24) {
          tagRow++;
          if (tagRow == 2) break;
          tagX = x + 24;
        }
        final tagY = y + 24 + (cardLayout.tagRows - 1 - tagRow) * 29;
        builder
          ..writeln('q 0.878 0.906 1 rg')
          ..writeln(_roundedRectPath(tagX, tagY, tagWidth, 21, 10.5))
          ..writeln('f Q');
        _appendText(
          builder,
          _ellipsizeToWidth(tag, tagWidth - 20, 11, font),
          tagX + 10,
          tagY + 5,
          11,
          '#3730A3',
          font,
        );
        tagX += tagWidth + 8;
      }
    }

    const watermark = '使用 UAF v1.0 导出';
    _appendText(
      builder,
      watermark,
      _pageWidth - 40 - font.textWidth(watermark, 10),
      40,
      10,
      '#94A3B8',
      font,
    );
    return builder.toString();
  }

  static _CardLayout _layoutCard(
    _AssignmentFragment assignment,
    _EmbeddedFont font,
  ) {
    final content = _fitContent(
      assignment.content,
      _bodyWidth,
      _bodyMaxHeight,
      font,
    );
    final tagRows = _tagRowCount(assignment.tags, font);
    final tagHeight = tagRows == 0
        ? 0.0
        : 20 + tagRows * 21 + (tagRows - 1) * 8;
    final height = math.min(
      _cardMaxHeight,
      115 + content.lines.length * content.lineHeight + tagHeight,
    );
    return _CardLayout(content, tagRows, height);
  }

  static int _tagRowCount(List<String> tags, _EmbeddedFont font) {
    if (tags.isEmpty) return 0;
    var row = 1;
    var used = 0.0;
    for (final tag in tags) {
      final width = math.min(font.textWidth(tag, 11) + 20, _bodyWidth);
      if (used > 0 && used + 8 + width > _bodyWidth) {
        row++;
        if (row > 2) return 2;
        used = 0;
      }
      used += width + (used == 0 ? 0 : 8);
    }
    return row;
  }

  static String _ellipsizeToWidth(
    String text,
    double width,
    double size,
    _EmbeddedFont font,
  ) {
    if (font.textWidth(text, size) <= width) return text;
    const ellipsis = '…';
    final result = StringBuffer();
    var used = font.textWidth(ellipsis, size);
    if (used > width) return '';
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final characterWidth = font.textWidth(character, size);
      if (used + characterWidth > width) break;
      result.write(character);
      used += characterWidth;
    }
    return '${result.toString()}$ellipsis';
  }

  static String _ellipsizeSubject(
    String text,
    double width,
    double size,
    _EmbeddedFont font,
  ) {
    if (font.textWidth(text, size) <= width) return text;
    const continuation = '（续）';
    if (!text.endsWith(continuation)) {
      return _ellipsizeToWidth(text, width, size, font);
    }

    final continuationWidth = font.textWidth(continuation, size);
    if (continuationWidth > width) {
      const compactContinuation = '续';
      if (font.textWidth(compactContinuation, size) <= width) {
        return compactContinuation;
      }
      return _ellipsizeToWidth(continuation, width, size, font);
    }
    final prefix = text.substring(0, text.length - continuation.length);
    final shortened = _ellipsizeToWidth(
      prefix,
      width - continuationWidth,
      size,
      font,
    );
    return '$shortened$continuation';
  }

  static _ContentLayout _fitContent(
    String content,
    double width,
    double maxHeight,
    _EmbeddedFont font,
  ) {
    for (final size in const <double>[22, 18, 16, 14]) {
      final lines = _wrapContent(content, width, size, font);
      final lineHeight = size * 1.5;
      if (lines.length * lineHeight <= maxHeight) {
        return _ContentLayout(size, lineHeight, lines);
      }
    }

    final finalLines = _wrapContent(content, width, _minimumBodyFontSize, font);
    if (finalLines.length * _minimumBodyLineHeight > maxHeight) {
      throw StateError('Assignment fragment does not fit its PDF card.');
    }
    return _ContentLayout(
      _minimumBodyFontSize,
      _minimumBodyLineHeight,
      finalLines,
    );
  }

  static List<String> _wrapContent(
    String content,
    double width,
    double fontSize,
    _EmbeddedFont font,
  ) {
    final lines = <String>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final paragraph in normalized.split('\n')) {
      final current = StringBuffer();
      var currentWidth = 0.0;
      for (final rune in paragraph.runes) {
        final text = String.fromCharCode(rune);
        final runeWidth = font.textWidth(text, fontSize);
        if (current.length > 0 && currentWidth + runeWidth > width) {
          lines.add(current.toString());
          current.clear();
          currentWidth = 0;
        }
        current.write(text);
        currentWidth += runeWidth;
      }
      lines.add(current.toString());
    }
    return lines;
  }

  static void _appendText(
    StringBuffer builder,
    String text,
    double x,
    double y,
    double size,
    String color,
    _EmbeddedFont font,
  ) {
    final rgb = _hexColor(color);
    builder
      ..writeln('BT')
      ..writeln('/F1 ${_formatNumber(size)} Tf')
      ..writeln(
        '${_formatNumber(rgb.$1)} ${_formatNumber(rgb.$2)} '
        '${_formatNumber(rgb.$3)} rg',
      )
      ..writeln('1 0 0 1 ${_formatNumber(x)} ${_formatNumber(y)} Tm')
      ..writeln('<${font.encode(text)}> Tj')
      ..writeln('ET');
  }

  static String _roundedRectPath(
    double x,
    double y,
    double width,
    double height,
    double radius,
  ) {
    final k = radius * 0.5522847498;
    final right = x + width;
    final top = y + height;
    return <String>[
      '${_formatNumber(x + radius)} ${_formatNumber(y)} m',
      '${_formatNumber(right - radius)} ${_formatNumber(y)} l',
      '${_formatNumber(right - radius + k)} ${_formatNumber(y)} '
          '${_formatNumber(right)} ${_formatNumber(y + radius - k)} '
          '${_formatNumber(right)} ${_formatNumber(y + radius)} c',
      '${_formatNumber(right)} ${_formatNumber(top - radius)} l',
      '${_formatNumber(right)} ${_formatNumber(top - radius + k)} '
          '${_formatNumber(right - radius + k)} ${_formatNumber(top)} '
          '${_formatNumber(right - radius)} ${_formatNumber(top)} c',
      '${_formatNumber(x + radius)} ${_formatNumber(top)} l',
      '${_formatNumber(x + radius - k)} ${_formatNumber(top)} '
          '${_formatNumber(x)} ${_formatNumber(top - radius + k)} '
          '${_formatNumber(x)} ${_formatNumber(top - radius)} c',
      '${_formatNumber(x)} ${_formatNumber(y + radius)} l',
      '${_formatNumber(x)} ${_formatNumber(y + radius - k)} '
          '${_formatNumber(x + radius - k)} ${_formatNumber(y)} '
          '${_formatNumber(x + radius)} ${_formatNumber(y)} c',
      'h',
    ].join('\n');
  }

  static String _formatDateZh(String date) {
    final match = RegExp(r'^([+-]?\d{4,6})-(\d{2})-(\d{2})').firstMatch(date);
    if (match == null) return date;
    return '${int.parse(match.group(1)!)}年'
        '${int.parse(match.group(2)!)}月'
        '${int.parse(match.group(3)!)}日';
  }

  static Uint8List _object(String value) {
    return Uint8List.fromList(ascii.encode(value));
  }

  static Uint8List _streamObject(String dictionary, Uint8List stream) {
    final output = BytesBuilder(copy: false)
      ..add(ascii.encode(dictionary))
      ..add(ascii.encode('\nstream\n'))
      ..add(stream)
      ..add(ascii.encode('\nendstream'));
    return output.takeBytes();
  }

  static String _toUtf16Hex(String value, {bool includeBom = false}) {
    final output = StringBuffer();
    if (includeBom) output.write('FEFF');
    for (final codeUnit in value.codeUnits) {
      output.write(codeUnit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    return output.toString();
  }

  static String _formatNumber(double value) {
    if (value == 0) return '0';
    final fixed = value.toStringAsFixed(3);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static (double, double, double) _hexColor(String hex) {
    final value = hex.startsWith('#') ? hex.substring(1) : hex;
    return (
      int.parse(value.substring(0, 2), radix: 16) / 255,
      int.parse(value.substring(2, 4), radix: 16) / 255,
      int.parse(value.substring(4, 6), radix: 16) / 255,
    );
  }

  static int _lastIndexOf(Uint8List haystack, Uint8List needle, {int? before}) {
    if (needle.isEmpty) {
      return math.min(before ?? haystack.length, haystack.length);
    }
    final lastStart = math.min(
      haystack.length - needle.length,
      (before ?? haystack.length) - 1,
    );
    for (var index = lastStart; index >= 0; index--) {
      var match = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (haystack[index + offset] != needle[offset]) {
          match = false;
          break;
        }
      }
      if (match) return index;
    }
    return -1;
  }

  static bool _startsWith(Uint8List haystack, Uint8List needle) {
    if (haystack.length < needle.length) return false;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[index] != needle[index]) return false;
    }
    return true;
  }

  static bool _matchesAscii(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static bool _isPdfWhitespace(int byte) {
    return byte == 0x00 ||
        byte == 0x09 ||
        byte == 0x0a ||
        byte == 0x0c ||
        byte == 0x0d ||
        byte == 0x20;
  }

  static bool _isDigit(int byte) => byte >= 0x30 && byte <= 0x39;
}

/// TypeScript-compatible shorthand for [UafPdf.create].
Uint8List createUafPdf(UafDocument payload) => UafPdf.create(payload);

/// TypeScript-compatible shorthand for [UafPdf.extractPayload].
UafDocument extractUafPayload(Uint8List pdfBytes) {
  return UafPdf.extractPayload(pdfBytes);
}

/// TypeScript-compatible shorthand for [UafPdf.extractPayloadCsv].
String extractUafPayloadCsv(Uint8List pdfBytes) {
  return UafPdf.extractPayloadCsv(pdfBytes);
}

/// TypeScript-compatible shorthand for [UafPdf.validate].
UafPdfValidationResult validateUafPdf(Uint8List pdfBytes) {
  return UafPdf.validate(pdfBytes);
}

final class _EmbeddedFont {
  _EmbeddedFont._({
    required this.subsetFont,
    required this.compressedFont,
    required this.compressedCidToGid,
    required this.toUnicodeBytes,
    required this.widthsArray,
    required Map<int, int> runeToCid,
    required Map<int, int> runeWidths,
  }) : _runeToCid = runeToCid,
       _runeWidths = runeWidths;

  factory _EmbeddedFont.build(UafDocument document) {
    final runes = <int>{};

    void addText(String text, {bool ignoreLineBreaks = false}) {
      for (final rune in text.runes) {
        if (ignoreLineBreaks && (rune == 0x0a || rune == 0x0d)) continue;
        runes.add(rune);
      }
    }

    addText(' …使用 UAF v1.0 导出（续）年月日');
    for (final assignment in document) {
      addText(assignment.subject);
      addText(assignment.date);
      addText(assignment.content, ignoreLineBreaks: true);
      for (final tag in assignment.tags) {
        addText(tag);
      }
    }

    final sourceParser = _sourceParser ??= TtfParser(
      _byteData(loadBundledNotoSansSc()),
    );
    final unsupportedRunes = runes
        .where((int rune) => (sourceParser.charToGlyphIndexMap[rune] ?? 0) == 0)
        .toList(growable: false);
    if (unsupportedRunes.isNotEmpty) {
      final descriptions = unsupportedRunes.map(_describeRune).join(', ');
      throw UafException(
        UafErrorCode.invalidPayload,
        'Cannot create a self-contained UAF PDF because the bundled '
        'Noto Sans SC font does not support: $descriptions.',
      );
    }

    final supportedRunes = runes.toList(growable: false);
    final subsetFont = TtfWriter(sourceParser).withChars(supportedRunes);
    final subsetGlyphByRune = <int, int>{
      for (var index = 0; index < supportedRunes.length; index++)
        supportedRunes[index]: index,
    };

    final runeToCid = <int, int>{};
    final runeWidths = <int, int>{};
    final glyphs = <int>[0];
    final widths = <int>[1000];
    for (final rune in runes) {
      final cid = glyphs.length;
      final glyph = subsetGlyphByRune[rune]!;
      final sourceGlyph = sourceParser.charToGlyphIndexMap[rune]!;
      final metrics = sourceParser.glyphInfoMap[sourceGlyph];
      final width = ((metrics?.advanceWidth ?? 1) * 1000)
          .round()
          .clamp(0, 2000)
          .toInt();
      runeToCid[rune] = cid;
      runeWidths[rune] = width;
      glyphs.add(glyph);
      widths.add(width);
    }

    final cidToGid = Uint8List(glyphs.length * 2);
    final cidView = ByteData.sublistView(cidToGid);
    for (var cid = 0; cid < glyphs.length; cid++) {
      cidView.setUint16(cid * 2, glyphs[cid], Endian.big);
    }

    final toUnicode = _buildToUnicode(runeToCid);
    return _EmbeddedFont._(
      subsetFont: subsetFont,
      compressedFont: Uint8List.fromList(
        const ZLibEncoder().encodeBytes(subsetFont),
      ),
      compressedCidToGid: Uint8List.fromList(
        const ZLibEncoder().encodeBytes(cidToGid),
      ),
      toUnicodeBytes: Uint8List.fromList(ascii.encode(toUnicode)),
      widthsArray: '[1 [${widths.skip(1).join(' ')}]]',
      runeToCid: runeToCid,
      runeWidths: runeWidths,
    );
  }

  final Uint8List subsetFont;
  final Uint8List compressedFont;
  final Uint8List compressedCidToGid;
  final Uint8List toUnicodeBytes;
  final String widthsArray;
  final Map<int, int> _runeToCid;
  final Map<int, int> _runeWidths;

  static TtfParser? _sourceParser;

  String encode(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final cid = _runeToCid[rune];
      if (cid == null) _throwUnexpectedUnsupportedRune(rune);
      buffer.write(cid.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    return buffer.toString();
  }

  double textWidth(String text, double size) {
    var width = 0;
    for (final rune in text.runes) {
      final runeWidth = _runeWidths[rune];
      if (runeWidth == null) _throwUnexpectedUnsupportedRune(rune);
      width += runeWidth;
    }
    return width * size / 1000;
  }

  static String _describeRune(int rune) {
    final codePoint = rune.toRadixString(16).padLeft(4, '0').toUpperCase();
    return 'U+$codePoint ${jsonEncode(String.fromCharCode(rune))}';
  }

  static Never _throwUnexpectedUnsupportedRune(int rune) {
    throw UafException(
      UafErrorCode.invalidPayload,
      'Cannot create a self-contained UAF PDF because the bundled '
      'Noto Sans SC font does not support: ${_describeRune(rune)}.',
    );
  }

  static ByteData _byteData(Uint8List bytes) {
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  }

  static String _buildToUnicode(Map<int, int> runeToCid) {
    final entries = runeToCid.entries.toList(growable: false);
    final buffer = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin')
      ..writeln('begincmap')
      ..writeln(
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) '
        '/Supplement 0 >> def',
      )
      ..writeln('/CMapName /UAFNotoSansSC-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');

    for (var offset = 0; offset < entries.length; offset += 100) {
      final chunk = entries.sublist(
        offset,
        math.min(offset + 100, entries.length),
      );
      buffer.writeln('${chunk.length} beginbfchar');
      for (final entry in chunk) {
        final cid = entry.value.toRadixString(16).padLeft(4, '0').toUpperCase();
        final unicode = String.fromCharCode(entry.key).codeUnits
            .map(
              (int codeUnit) =>
                  codeUnit.toRadixString(16).padLeft(4, '0').toUpperCase(),
            )
            .join();
        buffer.writeln('<$cid> <$unicode>');
      }
      buffer.writeln('endbfchar');
    }

    return (buffer
          ..writeln('endcmap')
          ..writeln('CMapName currentdict /CMap defineresource pop')
          ..writeln('end')
          ..writeln('end'))
        .toString();
  }
}

final class _PdfInspection {
  const _PdfInspection({required this.pageCount, required this.csv});

  final int pageCount;
  final String? csv;
}

abstract final class _PdfLimits {
  static const int maxInputBytes = 32 * 1024 * 1024;
  static const int maxCompressedStreamBytes = 8 * 1024 * 1024;
  static const int maxDecodedStreamBytes = 16 * 1024 * 1024;
  static const int maxTotalDecodedBytes = 32 * 1024 * 1024;
  static const int maxCompressionRatio = 200;
  static const int maxDecodedStreams = 256;
  static const int maxXrefSections = 32;
  static const int maxObjects = 50000;
  static const int maxObjectStreamObjects = 10000;
  static const int maxPageNodes = 20000;
  static const int maxNameTreeNodes = 1024;
  static const int maxNameEntries = 4096;
  static const int maxSyntaxDepth = 128;
  static const int maxCollectionEntries = 50000;
}

final class _PdfReader {
  _PdfReader(this._bytes);

  final Uint8List _bytes;
  final _DecodeBudget _decodeBudget = _DecodeBudget();
  final Map<int, _XrefEntry> _xref = <int, _XrefEntry>{};
  final Map<int, _PdfIndirectObject> _objects = <int, _PdfIndirectObject>{};
  final Set<int> _resolvingObjects = <int>{};
  final Set<int> _loadedObjectStreams = <int>{};
  final Set<int> _loadingObjectStreams = <int>{};
  final Set<_PdfRef> _visitedPageObjects = <_PdfRef>{};
  final Set<_PdfRef> _visitedNameNodes = <_PdfRef>{};

  _PdfRef? _root;
  var _encrypted = false;
  var _pageNodes = 0;
  var _nameNodes = 0;
  var _nameEntries = 0;

  _PdfInspection inspect() {
    _readCurrentCrossReference();
    if (_encrypted) {
      _throwCorrupt('Encrypted PDFs are not supported.');
    }

    final root = _root;
    if (root == null) {
      _throwCorrupt('The current PDF trailer does not declare /Root.');
    }
    final catalog = _expectDict(
      _resolveObject(root).value,
      'The trailer /Root object is not a Catalog dictionary.',
    );
    _expectType(catalog, 'Catalog', 'The trailer /Root is not a Catalog.');

    final pagesValue = catalog['Pages'];
    if (pagesValue is! _PdfRef) {
      _throwCorrupt('The Catalog /Pages entry must be an indirect reference.');
    }
    final pageCount = _walkPageTree(pagesValue, null, 0);
    if (pageCount < 1) {
      _throwCorrupt('PDF page tree must contain at least one page.');
    }

    final payloadBytes = _findPayloadBytes(catalog);
    if (payloadBytes == null) {
      return _PdfInspection(pageCount: pageCount, csv: null);
    }

    final decoded = UafCsv.decodeUtf8(payloadBytes);
    final candidate = decoded.replaceFirst(RegExp(r'[\t\r\n ]+$'), '');
    try {
      UafCsv.parse(candidate);
    } on UafException catch (error, stackTrace) {
      if (error.code == UafErrorCode.invalidCsv) rethrow;
      throw UafException(
        UafErrorCode.invalidCsv,
        'Embedded "${UafConstants.payloadFileName}" is not valid UAF CSV: '
        '${error.message}',
        error,
        stackTrace,
      );
    }
    return _PdfInspection(pageCount: pageCount, csv: '$candidate\n');
  }

  void _readCurrentCrossReference() {
    if (_bytes.length < 8 ||
        _bytes.length > _PdfLimits.maxInputBytes ||
        !UafPdf._startsWith(_bytes, UafPdf._pdfHeader)) {
      _throwCorrupt(
        _bytes.length > _PdfLimits.maxInputBytes
            ? 'PDF exceeds the ${_PdfLimits.maxInputBytes}-byte input limit.'
            : 'PDF bytes do not start with a PDF header.',
      );
    }

    final eofIndex = UafPdf._lastIndexOf(_bytes, UafPdf._eofMarker);
    final startXrefIndex = UafPdf._lastIndexOf(
      _bytes,
      UafPdf._startXrefMarker,
      before: eofIndex,
    );
    if (eofIndex < 0 || startXrefIndex < 0) {
      _throwCorrupt(
        'PDF is truncated or is missing its cross-reference trailer.',
      );
    }
    for (
      var index = eofIndex + UafPdf._eofMarker.length;
      index < _bytes.length;
      index++
    ) {
      if (!UafPdf._isPdfWhitespace(_bytes[index])) {
        _throwCorrupt('PDF contains data after the final %%EOF marker.');
      }
    }

    final trailerSyntax = _PdfSyntax(
      _bytes,
      position: startXrefIndex + UafPdf._startXrefMarker.length,
      end: eofIndex,
    );
    final xrefOffset = trailerSyntax.readInt('startxref offset');
    trailerSyntax.skipWhitespaceAndComments();
    if (!trailerSyntax.isAtEnd ||
        xrefOffset < 0 ||
        xrefOffset >= startXrefIndex) {
      _throwCorrupt('PDF startxref does not contain a valid byte offset.');
    }

    var offset = xrefOffset;
    final visitedOffsets = <int>{};
    for (var sectionIndex = 0; ; sectionIndex++) {
      if (sectionIndex == _PdfLimits.maxXrefSections) {
        _throwCorrupt('PDF contains too many cross-reference sections.');
      }
      if (offset < 0 ||
          offset >= startXrefIndex ||
          !visitedOffsets.add(offset)) {
        _throwCorrupt('PDF cross-reference chain is invalid or cyclic.');
      }

      final section = _readXrefSection(offset);
      final localEntries = Map<int, _XrefEntry>.of(section.entries);
      final hybridOffset = _optionalInt(section.trailer['XRefStm']);
      if (hybridOffset != null) {
        if (hybridOffset < 0 || hybridOffset >= startXrefIndex) {
          _throwCorrupt('Trailer /XRefStm points outside the PDF.');
        }
        final hybrid = _readXrefStream(hybridOffset);
        localEntries.addAll(hybrid.entries);
      }

      for (final entry in localEntries.entries) {
        _xref.putIfAbsent(entry.key, () => entry.value);
      }
      if (_xref.length > _PdfLimits.maxObjects) {
        _throwCorrupt('PDF exceeds the cross-reference object limit.');
      }

      final rootValue = section.trailer['Root'];
      if (_root == null && rootValue != null) {
        if (rootValue is! _PdfRef) {
          _throwCorrupt('Trailer /Root must be an indirect reference.');
        }
        _root = rootValue;
      }
      if (section.trailer['Encrypt'] != null &&
          section.trailer['Encrypt'] is! _PdfNull) {
        _encrypted = true;
      }

      final previous = _optionalInt(section.trailer['Prev']);
      if (previous == null) break;
      offset = previous;
    }

    if (_xref.isEmpty) {
      _throwCorrupt('PDF cross-reference section is empty.');
    }
  }

  _XrefSection _readXrefSection(int offset) {
    final syntax = _PdfSyntax(_bytes, position: offset);
    if (syntax.peekKeyword('xref')) {
      return _readTraditionalXref(syntax);
    }
    return _readXrefStream(offset);
  }

  _XrefSection _readTraditionalXref(_PdfSyntax syntax) {
    syntax.expectKeyword('xref');
    final entries = <int, _XrefEntry>{};
    while (!syntax.peekKeyword('trailer')) {
      final firstObject = syntax.readInt('xref subsection start');
      final count = syntax.readInt('xref subsection count');
      if (firstObject < 0 ||
          count < 0 ||
          firstObject + count > _PdfLimits.maxObjects) {
        _throwCorrupt('PDF xref subsection exceeds the object limit.');
      }
      for (var index = 0; index < count; index++) {
        final objectNumber = firstObject + index;
        final objectOffset = syntax.readInt('xref object offset');
        final generation = syntax.readInt('xref generation');
        final state = syntax.readKeyword('xref entry state');
        final entry = switch (state) {
          'n' => _XrefEntry.uncompressed(objectOffset, generation),
          'f' => const _XrefEntry.free(),
          _ => throw const UafException(
            UafErrorCode.corruptPdf,
            'PDF xref entry must end in n or f.',
          ),
        };
        if (entries.containsKey(objectNumber)) {
          _throwCorrupt('PDF xref section contains duplicate entries.');
        }
        entries[objectNumber] = entry;
      }
    }
    syntax.expectKeyword('trailer');
    final trailer = _expectDict(
      syntax.readValue(),
      'PDF trailer must be a dictionary.',
    );
    _validateTrailerSize(trailer);
    return _XrefSection(entries: entries, trailer: trailer);
  }

  _XrefSection _readXrefStream(int offset) {
    final object = _parseIndirectAt(offset);
    final dictionary = _expectDict(
      object.value,
      'Cross-reference stream must have a dictionary.',
    );
    _expectType(
      dictionary,
      'XRef',
      'PDF startxref object is not a cross-reference stream.',
    );
    final stream = object.stream;
    if (stream == null) {
      _throwCorrupt('Cross-reference stream has no stream data.');
    }
    final decoded = _decodeStream(dictionary, stream);

    final widths = _intArray(dictionary['W'], '/W');
    if (widths.length != 3 ||
        widths.any((int width) => width < 0 || width > 6) ||
        widths.every((int width) => width == 0)) {
      _throwCorrupt('Cross-reference stream /W must contain three widths.');
    }
    final size = _requiredInt(dictionary['Size'], '/Size');
    if (size <= 0 || size > _PdfLimits.maxObjects) {
      _throwCorrupt('Cross-reference stream /Size exceeds the object limit.');
    }
    final index = dictionary['Index'] == null
        ? <int>[0, size]
        : _intArray(dictionary['Index'], '/Index');
    if (index.isEmpty || index.length.isOdd) {
      _throwCorrupt('Cross-reference stream /Index is invalid.');
    }

    final rowWidth = widths[0] + widths[1] + widths[2];
    var expectedLength = 0;
    for (var pair = 0; pair < index.length; pair += 2) {
      final first = index[pair];
      final count = index[pair + 1];
      if (first < 0 || count < 0 || first + count > size) {
        _throwCorrupt('Cross-reference stream /Index exceeds /Size.');
      }
      expectedLength += count * rowWidth;
    }
    if (expectedLength != decoded.length) {
      _throwCorrupt('Cross-reference stream length does not match /W.');
    }

    final entries = <int, _XrefEntry>{};
    var cursor = 0;
    for (var pair = 0; pair < index.length; pair += 2) {
      final first = index[pair];
      final count = index[pair + 1];
      for (var item = 0; item < count; item++) {
        final fields = <int>[];
        for (final width in widths) {
          var value = 0;
          for (var byteIndex = 0; byteIndex < width; byteIndex++) {
            value = value * 256 + decoded[cursor++];
          }
          fields.add(value);
        }
        final type = widths[0] == 0 ? 1 : fields[0];
        final entry = switch (type) {
          0 => const _XrefEntry.free(),
          1 => _XrefEntry.uncompressed(fields[1], fields[2]),
          2 => _XrefEntry.compressed(fields[1], fields[2]),
          _ => throw const UafException(
            UafErrorCode.corruptPdf,
            'Cross-reference stream contains an unknown entry type.',
          ),
        };
        entries[first + item] = entry;
      }
    }
    _validateTrailerSize(dictionary);
    return _XrefSection(entries: entries, trailer: dictionary);
  }

  void _validateTrailerSize(_PdfDict trailer) {
    final size = _optionalInt(trailer['Size']);
    if (size != null && (size <= 0 || size > _PdfLimits.maxObjects)) {
      _throwCorrupt('PDF trailer /Size exceeds the object limit.');
    }
  }

  _PdfIndirectObject _resolveObject(_PdfRef reference) {
    final cached = _objects[reference.objectNumber];
    if (cached != null) {
      if (cached.reference != reference) {
        _throwCorrupt('PDF object generation does not match its reference.');
      }
      return cached;
    }

    final entry = _xref[reference.objectNumber];
    if (entry == null || entry.kind == _XrefKind.free) {
      _throwCorrupt('PDF references an object absent from the current xref.');
    }
    if (!_resolvingObjects.add(reference.objectNumber)) {
      _throwCorrupt('PDF indirect object references are cyclic.');
    }
    try {
      switch (entry.kind) {
        case _XrefKind.free:
          _throwCorrupt('PDF references a free xref entry.');
        case _XrefKind.uncompressed:
          if (entry.generation != reference.generation ||
              entry.offset < 0 ||
              entry.offset >= _bytes.length) {
            _throwCorrupt('PDF xref entry does not match its reference.');
          }
          final object = _parseIndirectAt(entry.offset, expected: reference);
          _objects[reference.objectNumber] = object;
          return object;
        case _XrefKind.compressed:
          if (reference.generation != 0) {
            _throwCorrupt('Compressed PDF objects must use generation zero.');
          }
          _loadObjectStream(entry.objectStreamNumber);
          final object = _objects[reference.objectNumber];
          if (object == null || object.reference != reference) {
            _throwCorrupt(
              'Object stream does not contain the referenced PDF object.',
            );
          }
          return object;
      }
    } finally {
      _resolvingObjects.remove(reference.objectNumber);
    }
  }

  void _loadObjectStream(int objectStreamNumber) {
    if (_loadedObjectStreams.contains(objectStreamNumber)) return;
    if (!_loadingObjectStreams.add(objectStreamNumber)) {
      _throwCorrupt('PDF object streams are cyclic.');
    }
    try {
      final entry = _xref[objectStreamNumber];
      if (entry == null || entry.kind != _XrefKind.uncompressed) {
        _throwCorrupt('PDF object stream is not an uncompressed xref object.');
      }
      final reference = _PdfRef(objectStreamNumber, entry.generation);
      final object = _resolveObject(reference);
      final dictionary = _expectDict(
        object.value,
        'Object stream must have a dictionary.',
      );
      _expectType(dictionary, 'ObjStm', 'Referenced stream is not /ObjStm.');
      final stream = object.stream;
      if (stream == null) {
        _throwCorrupt('Object stream has no stream data.');
      }
      final decoded = _decodeStream(dictionary, stream);
      final count = _requiredInt(dictionary['N'], '/N');
      final first = _requiredInt(dictionary['First'], '/First');
      if (count < 0 ||
          count > _PdfLimits.maxObjectStreamObjects ||
          first < 0 ||
          first > decoded.length) {
        _throwCorrupt('Object stream /N or /First is invalid.');
      }

      final header = _PdfSyntax(decoded, end: first);
      final objectNumbers = <int>[];
      final offsets = <int>[];
      for (var index = 0; index < count; index++) {
        objectNumbers.add(header.readInt('object stream object number'));
        offsets.add(header.readInt('object stream object offset'));
      }
      header.skipWhitespaceAndComments();
      if (!header.isAtEnd) {
        _throwCorrupt('Object stream header exceeds /First.');
      }

      for (var index = 0; index < count; index++) {
        final objectNumber = objectNumbers[index];
        final relativeStart = offsets[index];
        final relativeEnd = index + 1 < count
            ? offsets[index + 1]
            : decoded.length - first;
        if (objectNumber <= 0 ||
            relativeStart < 0 ||
            relativeEnd < relativeStart ||
            first + relativeEnd > decoded.length) {
          _throwCorrupt('Object stream entry offset is invalid.');
        }
        final currentEntry = _xref[objectNumber];
        if (currentEntry == null ||
            currentEntry.kind != _XrefKind.compressed ||
            currentEntry.objectStreamNumber != objectStreamNumber ||
            currentEntry.objectStreamIndex != index) {
          continue;
        }
        final syntax = _PdfSyntax(
          decoded,
          position: first + relativeStart,
          end: first + relativeEnd,
        );
        final value = syntax.readValue();
        syntax.skipWhitespaceAndComments();
        if (!syntax.isAtEnd) {
          _throwCorrupt('Object stream entry contains trailing data.');
        }
        _objects[objectNumber] = _PdfIndirectObject(
          reference: _PdfRef(objectNumber, 0),
          value: value,
        );
      }
      _loadedObjectStreams.add(objectStreamNumber);
    } finally {
      _loadingObjectStreams.remove(objectStreamNumber);
    }
  }

  _PdfIndirectObject _parseIndirectAt(int offset, {_PdfRef? expected}) {
    final syntax = _PdfSyntax(_bytes, position: offset);
    final objectNumber = syntax.readInt('indirect object number');
    final generation = syntax.readInt('indirect object generation');
    final reference = _PdfRef(objectNumber, generation);
    if (objectNumber <= 0 ||
        generation < 0 ||
        (expected != null && reference != expected)) {
      _throwCorrupt('PDF xref offset points to the wrong indirect object.');
    }
    syntax.expectKeyword('obj');
    final value = syntax.readValue();

    _PdfStreamSlice? stream;
    if (value is _PdfDict && syntax.consumeKeyword('stream')) {
      if (syntax.isAtEnd) {
        _throwCorrupt('PDF stream is missing its line ending.');
      }
      if (syntax.currentByte == 0x0d) {
        syntax.position++;
        if (!syntax.isAtEnd && syntax.currentByte == 0x0a) {
          syntax.position++;
        }
      } else if (syntax.currentByte == 0x0a) {
        syntax.position++;
      } else {
        _throwCorrupt('PDF stream keyword must be followed by a line ending.');
      }

      final lengthValue = value['Length'];
      if (lengthValue is! int ||
          lengthValue < 0 ||
          lengthValue > _PdfLimits.maxCompressedStreamBytes ||
          syntax.position + lengthValue > _bytes.length) {
        _throwCorrupt('PDF stream /Length is missing or exceeds its limit.');
      }
      stream = _PdfStreamSlice(syntax.position, lengthValue);
      syntax.position += lengthValue;
      syntax.expectKeyword('endstream');
    }
    syntax.expectKeyword('endobj');
    return _PdfIndirectObject(
      reference: reference,
      value: value,
      stream: stream,
    );
  }

  Uint8List _decodeStream(_PdfDict dictionary, _PdfStreamSlice stream) {
    if (stream.length > _PdfLimits.maxCompressedStreamBytes ||
        stream.offset < 0 ||
        stream.offset + stream.length > _bytes.length) {
      _throwCorrupt('PDF stream exceeds the compressed input limit.');
    }
    final bytes = Uint8List.sublistView(
      _bytes,
      stream.offset,
      stream.offset + stream.length,
    );
    final filterValue = dictionary['Filter'];
    if (filterValue == null || filterValue is _PdfNull) {
      _decodeBudget.consume(bytes.length);
      return bytes;
    }

    final filters = filterValue is List<Object?>
        ? filterValue
        : <Object?>[filterValue];
    if (filters.length != 1 ||
        filters.single is! _PdfName ||
        (filters.single as _PdfName).value != 'FlateDecode') {
      _throwCorrupt('Only a declared /FlateDecode stream is supported.');
    }
    final decodeParameters = dictionary['DecodeParms'];
    if (decodeParameters != null && decodeParameters is! _PdfNull) {
      _throwCorrupt('FlateDecode predictor parameters are not supported.');
    }
    return _inflateFlate(bytes);
  }

  Uint8List _inflateFlate(Uint8List bytes) {
    _decodeBudget.beginStream();
    if (bytes.length < 6) {
      _throwCorrupt('FlateDecode stream is too short.');
    }
    final cmf = bytes[0];
    final flg = bytes[1];
    if ((cmf & 0x0f) != 8 ||
        (cmf >> 4) > 7 ||
        ((cmf << 8) + flg) % 31 != 0 ||
        (flg & 0x20) != 0) {
      _throwCorrupt('FlateDecode stream has an invalid zlib header.');
    }
    final ratioLimit = bytes.length * _PdfLimits.maxCompressionRatio;
    final outputLimit = math.min(_PdfLimits.maxDecodedStreamBytes, ratioLimit);
    final output = _LimitedOutputStream(outputLimit);
    try {
      Inflate(
        Uint8List.sublistView(bytes, 2, bytes.length - 4),
        output: output,
      );
    } on _PdfLimitException {
      _throwCorrupt('FlateDecode stream exceeds its output or ratio limit.');
    } on Object catch (error, stackTrace) {
      throw UafException(
        UafErrorCode.corruptPdf,
        'FlateDecode stream cannot be decompressed.',
        error,
        stackTrace,
      );
    }
    final decoded = Uint8List.fromList(output.getBytes());
    final expectedAdler =
        bytes[bytes.length - 4] * 0x1000000 +
        bytes[bytes.length - 3] * 0x10000 +
        bytes[bytes.length - 2] * 0x100 +
        bytes[bytes.length - 1];
    if (getAdler32(decoded) != expectedAdler) {
      _throwCorrupt('FlateDecode stream checksum is invalid.');
    }
    _decodeBudget.consumeDecoded(decoded.length);
    return decoded;
  }

  int _walkPageTree(_PdfRef reference, _PdfRef? expectedParent, int depth) {
    if (depth > _PdfLimits.maxSyntaxDepth ||
        !_visitedPageObjects.add(reference) ||
        ++_pageNodes > _PdfLimits.maxPageNodes) {
      _throwCorrupt('PDF page tree is cyclic or exceeds its node limit.');
    }
    final dictionary = _expectDict(
      _resolveObject(reference).value,
      'PDF page-tree node must be a dictionary.',
    );
    final type = _nameValue(dictionary['Type']);
    final parent = dictionary['Parent'];
    if (expectedParent != null && parent != expectedParent) {
      _throwCorrupt('PDF page-tree /Parent link is inconsistent.');
    }
    if (type == 'Page') return 1;
    if (type != 'Pages') {
      _throwCorrupt(
        'PDF page tree contains a node without /Type /Pages or /Page.',
      );
    }

    final kids = dictionary['Kids'];
    if (kids is! List<Object?> || kids.isEmpty) {
      _throwCorrupt('PDF /Pages node must contain a non-empty /Kids array.');
    }
    var count = 0;
    for (final kid in kids) {
      if (kid is! _PdfRef) {
        _throwCorrupt('PDF page-tree kids must be indirect references.');
      }
      count += _walkPageTree(kid, reference, depth + 1);
      if (count > _PdfLimits.maxPageNodes) {
        _throwCorrupt('PDF page count exceeds its safety limit.');
      }
    }
    final declaredCount = _requiredInt(dictionary['Count'], '/Count');
    if (declaredCount != count) {
      _throwCorrupt('PDF /Pages /Count does not match the current page tree.');
    }
    return count;
  }

  Uint8List? _findPayloadBytes(_PdfDict catalog) {
    final namesValue = catalog['Names'];
    if (namesValue == null || namesValue is _PdfNull) return null;
    final names = _resolveDict(namesValue, 'Catalog /Names');
    final embeddedValue = names['EmbeddedFiles'];
    if (embeddedValue == null || embeddedValue is _PdfNull) return null;
    final embedded = _resolveDict(embeddedValue, '/EmbeddedFiles');
    return _searchNameTree(embedded, null, 0);
  }

  Uint8List? _searchNameTree(_PdfDict node, _PdfRef? nodeReference, int depth) {
    if (depth > _PdfLimits.maxSyntaxDepth ||
        ++_nameNodes > _PdfLimits.maxNameTreeNodes ||
        (nodeReference != null && !_visitedNameNodes.add(nodeReference))) {
      _throwCorrupt('Embedded-files name tree is cyclic or too large.');
    }

    final namesValue = node['Names'];
    if (namesValue != null && namesValue is! _PdfNull) {
      if (namesValue is! List<Object?> || namesValue.length.isOdd) {
        _throwCorrupt('Embedded-files /Names must contain name/value pairs.');
      }
      final names = namesValue;
      for (var index = 0; index < names.length; index += 2) {
        if (++_nameEntries > _PdfLimits.maxNameEntries) {
          _throwCorrupt('Embedded-files name tree exceeds its entry limit.');
        }
        final nameValue = names[index];
        if (nameValue is! _PdfText) {
          _throwCorrupt('Embedded-files name-tree keys must be PDF strings.');
        }
        final treeName = nameValue.decode();
        final fileSpecValue = names[index + 1];
        final fileSpec = _resolveDict(fileSpecValue, 'embedded FileSpec');
        final specName = _fileSpecName(fileSpec);
        if (treeName == UafConstants.payloadFileName &&
            specName == UafConstants.payloadFileName) {
          return _readEmbeddedFile(fileSpec);
        }
      }
    }

    final kidsValue = node['Kids'];
    if (kidsValue != null && kidsValue is! _PdfNull) {
      if (kidsValue is! List<Object?>) {
        _throwCorrupt('Embedded-files /Kids must be an array.');
      }
      for (final kid in kidsValue) {
        if (kid is! _PdfRef) {
          _throwCorrupt('Embedded-files name-tree kids must be references.');
        }
        final reference = kid;
        final child = _expectDict(
          _resolveObject(reference).value,
          'Embedded-files name-tree child must be a dictionary.',
        );
        final found = _searchNameTree(child, reference, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  String? _fileSpecName(_PdfDict fileSpec) {
    final unicodeName = fileSpec['UF'];
    if (unicodeName == null || unicodeName is _PdfNull) return null;
    if (unicodeName is! _PdfText) {
      _throwCorrupt('FileSpec /UF must be a PDF string.');
    }
    return unicodeName.decode();
  }

  Uint8List _readEmbeddedFile(_PdfDict fileSpec) {
    final type = fileSpec['Type'];
    if (type != null && _nameValue(type) != 'Filespec') {
      _throwCorrupt('Embedded payload entry is not a FileSpec dictionary.');
    }
    final ef = _resolveDict(fileSpec['EF'], 'FileSpec /EF');
    final streamValue = ef['UF'] ?? ef['F'];
    if (streamValue is! _PdfRef) {
      _throwCorrupt('FileSpec /EF must reference an embedded-file stream.');
    }
    final streamObject = _resolveObject(streamValue);
    final dictionary = _expectDict(
      streamObject.value,
      'Embedded-file object must have a stream dictionary.',
    );
    final stream = streamObject.stream;
    if (stream == null) {
      _throwCorrupt('FileSpec /EF reference does not point to a stream.');
    }
    return _decodeStream(dictionary, stream);
  }

  _PdfDict _resolveDict(Object? value, String label) {
    if (value is _PdfRef) {
      return _expectDict(
        _resolveObject(value).value,
        '$label must resolve to a dictionary.',
      );
    }
    return _expectDict(value, '$label must be a dictionary.');
  }

  static _PdfDict _expectDict(Object? value, String message) {
    if (value is _PdfDict) return value;
    _throwCorrupt(message);
  }

  static void _expectType(_PdfDict dictionary, String type, String message) {
    if (_nameValue(dictionary['Type']) != type) _throwCorrupt(message);
  }

  static String? _nameValue(Object? value) {
    return value is _PdfName ? value.value : null;
  }

  static int _requiredInt(Object? value, String name) {
    if (value is int) return value;
    _throwCorrupt('PDF $name must be an integer.');
  }

  static int? _optionalInt(Object? value) {
    if (value == null || value is _PdfNull) return null;
    if (value is int) return value;
    _throwCorrupt('PDF numeric entry must be an integer.');
  }

  static List<int> _intArray(Object? value, String name) {
    if (value is! List<Object?>) {
      _throwCorrupt('PDF $name must be an integer array.');
    }
    final output = <int>[];
    for (final item in value) {
      if (item is! int) {
        _throwCorrupt('PDF $name must contain only integers.');
      }
      output.add(item);
    }
    return output;
  }

  static Never _throwCorrupt(String message) {
    throw UafException(UafErrorCode.corruptPdf, message);
  }
}

final class _PdfSyntax {
  _PdfSyntax(this.bytes, {this.position = 0, int? end})
    : end = end ?? bytes.length {
    if (position < 0 || position > this.end || this.end > bytes.length) {
      _PdfReader._throwCorrupt('PDF parser bounds are invalid.');
    }
  }

  final Uint8List bytes;
  final int end;
  int position;

  bool get isAtEnd => position >= end;
  int get currentByte => bytes[position];

  void skipWhitespaceAndComments() {
    while (position < end) {
      if (UafPdf._isPdfWhitespace(bytes[position])) {
        position++;
        continue;
      }
      if (bytes[position] == 0x25) {
        position++;
        while (position < end &&
            bytes[position] != 0x0a &&
            bytes[position] != 0x0d) {
          position++;
        }
        continue;
      }
      break;
    }
  }

  bool peekKeyword(String keyword) {
    final saved = position;
    final result = consumeKeyword(keyword);
    position = saved;
    return result;
  }

  bool consumeKeyword(String keyword) {
    final saved = position;
    skipWhitespaceAndComments();
    if (!UafPdf._matchesAscii(bytes, position, keyword)) {
      position = saved;
      return false;
    }
    final after = position + keyword.length;
    if (after < end && !_isDelimiterOrWhitespace(bytes[after])) {
      position = saved;
      return false;
    }
    position = after;
    return true;
  }

  void expectKeyword(String keyword) {
    if (!consumeKeyword(keyword)) {
      _PdfReader._throwCorrupt('Expected PDF keyword "$keyword".');
    }
  }

  String readKeyword(String label) {
    skipWhitespaceAndComments();
    final start = position;
    while (position < end && !_isDelimiterOrWhitespace(bytes[position])) {
      position++;
    }
    if (position == start) {
      _PdfReader._throwCorrupt('Missing PDF $label.');
    }
    return ascii.decode(Uint8List.sublistView(bytes, start, position));
  }

  int readInt(String label) {
    skipWhitespaceAndComments();
    final value = _readNumber();
    if (value is! int) {
      _PdfReader._throwCorrupt('PDF $label must be an integer.');
    }
    return value;
  }

  Object? readValue([int depth = 0]) {
    if (depth > _PdfLimits.maxSyntaxDepth) {
      _PdfReader._throwCorrupt('PDF object nesting exceeds its limit.');
    }
    skipWhitespaceAndComments();
    if (isAtEnd) _PdfReader._throwCorrupt('Unexpected end of PDF object.');
    final byte = currentByte;
    if (byte == 0x2f) return _readName();
    if (byte == 0x28) return _readLiteralString();
    if (byte == 0x3c) {
      if (position + 1 < end && bytes[position + 1] == 0x3c) {
        return _readDictionary(depth + 1);
      }
      return _readHexString();
    }
    if (byte == 0x5b) return _readArray(depth + 1);
    if (_isNumberStart(byte)) {
      final first = _readNumber();
      if (first is int) {
        final afterFirst = position;
        skipWhitespaceAndComments();
        if (!isAtEnd && _isNumberStart(currentByte)) {
          final second = _readNumber();
          if (second is int && consumeKeyword('R')) {
            if (first <= 0 || second < 0) {
              _PdfReader._throwCorrupt('PDF indirect reference is invalid.');
            }
            return _PdfRef(first, second);
          }
        }
        position = afterFirst;
      }
      return first;
    }

    final keyword = readKeyword('object value');
    return switch (keyword) {
      'true' => true,
      'false' => false,
      'null' => const _PdfNull(),
      _ => _PdfKeyword(keyword),
    };
  }

  _PdfName _readName() {
    position++;
    final output = BytesBuilder(copy: false);
    while (position < end && !_isDelimiterOrWhitespace(bytes[position])) {
      final byte = bytes[position++];
      if (byte == 0x23) {
        if (position + 1 >= end) {
          _PdfReader._throwCorrupt('PDF name contains an incomplete escape.');
        }
        final high = _hexValue(bytes[position++]);
        final low = _hexValue(bytes[position++]);
        if (high < 0 || low < 0) {
          _PdfReader._throwCorrupt('PDF name contains an invalid escape.');
        }
        output.addByte(high * 16 + low);
      } else {
        output.addByte(byte);
      }
    }
    return _PdfName(latin1.decode(output.takeBytes()));
  }

  _PdfText _readLiteralString() {
    position++;
    var nesting = 1;
    final output = BytesBuilder(copy: false);
    while (position < end) {
      final byte = bytes[position++];
      if (byte == 0x28) {
        nesting++;
        output.addByte(byte);
        continue;
      }
      if (byte == 0x29) {
        nesting--;
        if (nesting == 0) return _PdfText(output.takeBytes());
        output.addByte(byte);
        continue;
      }
      if (byte != 0x5c) {
        output.addByte(byte);
        continue;
      }
      if (position >= end) break;
      final escaped = bytes[position++];
      switch (escaped) {
        case 0x6e:
          output.addByte(0x0a);
        case 0x72:
          output.addByte(0x0d);
        case 0x74:
          output.addByte(0x09);
        case 0x62:
          output.addByte(0x08);
        case 0x66:
          output.addByte(0x0c);
        case 0x28 || 0x29 || 0x5c:
          output.addByte(escaped);
        case 0x0d:
          if (position < end && bytes[position] == 0x0a) position++;
        case 0x0a:
          break;
        default:
          if (escaped >= 0x30 && escaped <= 0x37) {
            var value = escaped - 0x30;
            var digits = 1;
            while (digits < 3 &&
                position < end &&
                bytes[position] >= 0x30 &&
                bytes[position] <= 0x37) {
              value = value * 8 + bytes[position++] - 0x30;
              digits++;
            }
            output.addByte(value & 0xff);
          } else {
            output.addByte(escaped);
          }
      }
    }
    _PdfReader._throwCorrupt('PDF literal string is unterminated.');
  }

  _PdfText _readHexString() {
    position++;
    final output = BytesBuilder(copy: false);
    int? high;
    while (position < end) {
      final byte = bytes[position++];
      if (byte == 0x3e) {
        if (high != null) output.addByte(high * 16);
        return _PdfText(output.takeBytes());
      }
      if (UafPdf._isPdfWhitespace(byte)) continue;
      final value = _hexValue(byte);
      if (value < 0) {
        _PdfReader._throwCorrupt('PDF hex string contains a non-hex byte.');
      }
      if (high == null) {
        high = value;
      } else {
        output.addByte(high * 16 + value);
        high = null;
      }
    }
    _PdfReader._throwCorrupt('PDF hex string is unterminated.');
  }

  List<Object?> _readArray(int depth) {
    position++;
    final values = <Object?>[];
    while (true) {
      skipWhitespaceAndComments();
      if (isAtEnd) _PdfReader._throwCorrupt('PDF array is unterminated.');
      if (currentByte == 0x5d) {
        position++;
        return values;
      }
      if (values.length == _PdfLimits.maxCollectionEntries) {
        _PdfReader._throwCorrupt('PDF array exceeds its entry limit.');
      }
      values.add(readValue(depth));
    }
  }

  _PdfDict _readDictionary(int depth) {
    position += 2;
    final values = <String, Object?>{};
    while (true) {
      skipWhitespaceAndComments();
      if (position + 1 < end &&
          bytes[position] == 0x3e &&
          bytes[position + 1] == 0x3e) {
        position += 2;
        return _PdfDict(values);
      }
      if (isAtEnd || currentByte != 0x2f) {
        _PdfReader._throwCorrupt('PDF dictionary is unterminated.');
      }
      if (values.length == _PdfLimits.maxCollectionEntries) {
        _PdfReader._throwCorrupt('PDF dictionary exceeds its entry limit.');
      }
      final key = _readName().value;
      values[key] = readValue(depth);
    }
  }

  num _readNumber() {
    final start = position;
    while (position < end && !_isDelimiterOrWhitespace(bytes[position])) {
      position++;
    }
    if (position == start) {
      _PdfReader._throwCorrupt('Missing PDF number.');
    }
    final text = ascii.decode(Uint8List.sublistView(bytes, start, position));
    final integer = int.tryParse(text);
    if (integer != null) return integer;
    final decimal = double.tryParse(text);
    if (decimal == null || !decimal.isFinite) {
      _PdfReader._throwCorrupt('PDF number is invalid.');
    }
    return decimal;
  }

  static bool _isNumberStart(int byte) {
    return UafPdf._isDigit(byte) ||
        byte == 0x2b ||
        byte == 0x2d ||
        byte == 0x2e;
  }

  static bool _isDelimiterOrWhitespace(int byte) {
    return UafPdf._isPdfWhitespace(byte) ||
        byte == 0x28 ||
        byte == 0x29 ||
        byte == 0x3c ||
        byte == 0x3e ||
        byte == 0x5b ||
        byte == 0x5d ||
        byte == 0x7b ||
        byte == 0x7d ||
        byte == 0x2f ||
        byte == 0x25;
  }

  static int _hexValue(int byte) {
    if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
    if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
    if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
    return -1;
  }
}

final class _DecodeBudget {
  var _streams = 0;
  var _decodedBytes = 0;

  void beginStream() {
    if (++_streams > _PdfLimits.maxDecodedStreams) {
      _PdfReader._throwCorrupt('PDF exceeds the decoded-stream count limit.');
    }
  }

  void consume(int bytes) {
    beginStream();
    if (bytes > _PdfLimits.maxDecodedStreamBytes) {
      _PdfReader._throwCorrupt('PDF stream exceeds the decoded output limit.');
    }
    consumeDecoded(bytes);
  }

  void consumeDecoded(int bytes) {
    _decodedBytes += bytes;
    if (_decodedBytes > _PdfLimits.maxTotalDecodedBytes) {
      _PdfReader._throwCorrupt('PDF exceeds the total decoded-byte limit.');
    }
  }
}

final class _LimitedOutputStream extends OutputMemoryStream {
  _LimitedOutputStream(this.limit)
    : super(size: math.max(1, math.min(limit, 0x8000)));

  final int limit;

  void _check(int additional) {
    if (additional < 0 || length + additional > limit) {
      throw const _PdfLimitException();
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final actualLength = length ?? bytes.length;
    _check(actualLength);
    super.writeBytes(bytes, length: actualLength);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}

final class _PdfLimitException implements Exception {
  const _PdfLimitException();
}

enum _XrefKind { free, uncompressed, compressed }

final class _XrefEntry {
  const _XrefEntry.free()
    : kind = _XrefKind.free,
      offset = 0,
      generation = 0,
      objectStreamNumber = 0,
      objectStreamIndex = 0;

  const _XrefEntry.uncompressed(this.offset, this.generation)
    : kind = _XrefKind.uncompressed,
      objectStreamNumber = 0,
      objectStreamIndex = 0;

  const _XrefEntry.compressed(this.objectStreamNumber, this.objectStreamIndex)
    : kind = _XrefKind.compressed,
      offset = 0,
      generation = 0;

  final _XrefKind kind;
  final int offset;
  final int generation;
  final int objectStreamNumber;
  final int objectStreamIndex;
}

final class _XrefSection {
  const _XrefSection({required this.entries, required this.trailer});

  final Map<int, _XrefEntry> entries;
  final _PdfDict trailer;
}

final class _PdfIndirectObject {
  const _PdfIndirectObject({
    required this.reference,
    required this.value,
    this.stream,
  });

  final _PdfRef reference;
  final Object? value;
  final _PdfStreamSlice? stream;
}

final class _PdfStreamSlice {
  const _PdfStreamSlice(this.offset, this.length);

  final int offset;
  final int length;
}

final class _PdfRef {
  const _PdfRef(this.objectNumber, this.generation);

  final int objectNumber;
  final int generation;

  @override
  bool operator ==(Object other) {
    return other is _PdfRef &&
        other.objectNumber == objectNumber &&
        other.generation == generation;
  }

  @override
  int get hashCode => Object.hash(objectNumber, generation);
}

final class _PdfDict {
  const _PdfDict(this.values);

  final Map<String, Object?> values;

  Object? operator [](String key) => values[key];
}

final class _PdfName {
  const _PdfName(this.value);

  final String value;
}

final class _PdfText {
  const _PdfText(this.bytes);

  final Uint8List bytes;

  String decode() {
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _decodeUtf16(bigEndian: true, offset: 2);
    }
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _decodeUtf16(bigEndian: false, offset: 2);
    }
    if (bytes.length.isEven && bytes.isNotEmpty) {
      var looksLikeUtf16 = true;
      for (var index = 0; index < bytes.length; index += 2) {
        if (bytes[index] != 0) {
          looksLikeUtf16 = false;
          break;
        }
      }
      if (looksLikeUtf16) return _decodeUtf16(bigEndian: true, offset: 0);
    }
    return latin1.decode(bytes);
  }

  String _decodeUtf16({required bool bigEndian, required int offset}) {
    if ((bytes.length - offset).isOdd) {
      _PdfReader._throwCorrupt('PDF UTF-16 string has an odd byte length.');
    }
    final codeUnits = <int>[];
    for (var index = offset; index < bytes.length; index += 2) {
      codeUnits.add(
        bigEndian
            ? bytes[index] * 256 + bytes[index + 1]
            : bytes[index + 1] * 256 + bytes[index],
      );
    }
    return String.fromCharCodes(codeUnits);
  }
}

final class _PdfKeyword {
  const _PdfKeyword(this.value);

  final String value;
}

final class _PdfNull {
  const _PdfNull();
}

final class _AssignmentFragment {
  const _AssignmentFragment({
    required this.subject,
    required this.date,
    required this.content,
    required this.tags,
  });

  final String subject;
  final String date;
  final String content;
  final List<String> tags;
}

final class _ContentLayout {
  const _ContentLayout(this.fontSize, this.lineHeight, this.lines);

  final double fontSize;
  final double lineHeight;
  final List<String> lines;
}

final class _CardLayout {
  const _CardLayout(this.content, this.tagRows, this.height);

  final _ContentLayout content;
  final int tagRows;
  final double height;
}
