import 'dart:convert';
import 'dart:typed_data';

import 'constants.dart';
import 'errors.dart';
import 'model.dart';

/// RFC 4180 CSV encoding and decoding for UAF v1.0 payloads.
abstract final class UafCsv {
  /// Serializes [document] with the exact UAF header and a final LF.
  ///
  /// Fields containing a comma, quote, CR, or LF are quoted and embedded
  /// quotes are doubled. Assignment order is preserved.
  static String serialize(UafDocument document) {
    final buffer = StringBuffer()..writeln(UafConstants.csvHeader);
    for (final assignment in document) {
      buffer
        ..write(_escapeField(assignment.subject))
        ..write(',')
        ..write(_escapeField(assignment.date))
        ..write(',')
        ..write(_escapeField(assignment.content))
        ..write(',')
        ..writeln(_escapeField(assignment.tags.join(';')));
    }
    return buffer.toString();
  }

  /// Serializes [document] as UTF-8 bytes without a byte-order mark (BOM).
  static Uint8List serializeToUtf8(UafDocument document) {
    return Uint8List.fromList(utf8.encode(serialize(document)));
  }

  /// Parses a UAF CSV string and validates every assignment.
  ///
  /// A leading Unicode BOM is tolerated for compatibility when reading, even
  /// though [serializeToUtf8] never emits one.
  static UafDocument parse(String csv) {
    var normalized = csv;
    if (normalized.startsWith('\uFEFF')) {
      normalized = normalized.substring(1);
    }

    final rows = _splitRows(normalized);
    if (rows.length < 2) {
      throw const UafException(
        UafErrorCode.invalidCsv,
        'CSV must contain a header and at least one data row.',
      );
    }

    if (rows.first != UafConstants.csvHeader) {
      throw UafException(
        UafErrorCode.invalidCsv,
        'Invalid CSV header: expected "${UafConstants.csvHeader}".',
      );
    }

    final assignments = <UafAssignment>[];
    for (var index = 1; index < rows.length; index++) {
      final fields = _parseRow(rows[index]);
      if (fields.length != UafConstants.fieldNames.length) {
        throw UafException(
          UafErrorCode.invalidCsv,
          'Row ${index + 1}: expected ${UafConstants.fieldNames.length} '
          'columns, got ${fields.length}.',
        );
      }
      try {
        assignments.add(
          UafAssignment(
            subject: fields[0],
            date: fields[1],
            content: fields[2],
            tags: _tagsFromCsv(fields[3]),
          ),
        );
      } on UafException catch (error, stackTrace) {
        throw UafException(
          error.code,
          'Row ${index + 1}: ${error.message}',
          error,
          stackTrace,
        );
      }
    }
    return UafDocument(assignments);
  }

  /// Strictly decodes [bytes] as UTF-8 and parses the resulting CSV.
  static UafDocument parseUtf8(List<int> bytes) => parse(decodeUtf8(bytes));

  /// Strictly decodes UTF-8 [bytes]. Malformed sequences are rejected.
  static String decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error, stackTrace) {
      throw UafException(
        UafErrorCode.invalidCsv,
        'CSV must be valid UTF-8.',
        error,
        stackTrace,
      );
    } on RangeError catch (error, stackTrace) {
      throw UafException(
        UafErrorCode.invalidCsv,
        'CSV bytes must each be in the range 0 through 255.',
        error,
        stackTrace,
      );
    }
  }

  static String _escapeField(String value) {
    if (!value.contains(RegExp(r'[",\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static List<String> _splitRows(String text) {
    final rows = <String>[];
    final row = StringBuffer();
    var quoted = false;
    var endedWithRecordDelimiter = false;

    for (var index = 0; index < text.length; index++) {
      final codeUnit = text.codeUnitAt(index);
      if (codeUnit == _quote) {
        if (quoted &&
            index + 1 < text.length &&
            text.codeUnitAt(index + 1) == _quote) {
          row.write('""');
          index++;
          continue;
        }
        quoted = !quoted;
        row.writeCharCode(codeUnit);
        endedWithRecordDelimiter = false;
        continue;
      }

      if (!quoted && codeUnit == _carriageReturn) {
        if (index + 1 >= text.length ||
            text.codeUnitAt(index + 1) != _lineFeed) {
          throw const UafException(
            UafErrorCode.invalidCsv,
            'CSV record delimiters must be LF or CRLF.',
          );
        }
        index++;
        rows.add(row.toString());
        row.clear();
        endedWithRecordDelimiter = true;
        continue;
      }
      if (!quoted && codeUnit == _lineFeed) {
        rows.add(row.toString());
        row.clear();
        endedWithRecordDelimiter = true;
        continue;
      }
      row.writeCharCode(codeUnit);
      endedWithRecordDelimiter = false;
    }

    if (quoted) {
      throw const UafException(
        UafErrorCode.invalidCsv,
        'CSV contains an unterminated quoted field.',
      );
    }
    if (!endedWithRecordDelimiter) {
      rows.add(row.toString());
    }
    return rows;
  }

  static List<String> _parseRow(String row) {
    final fields = <String>[];
    var index = 0;

    while (true) {
      final field = StringBuffer();
      if (index < row.length && row.codeUnitAt(index) == _quote) {
        index++;
        var closed = false;
        while (index < row.length) {
          final codeUnit = row.codeUnitAt(index);
          if (codeUnit != _quote) {
            field.writeCharCode(codeUnit);
            index++;
            continue;
          }
          if (index + 1 < row.length && row.codeUnitAt(index + 1) == _quote) {
            field.writeCharCode(_quote);
            index += 2;
            continue;
          }
          index++;
          closed = true;
          break;
        }
        if (!closed) {
          throw const UafException(
            UafErrorCode.invalidCsv,
            'CSV contains an unterminated quoted field.',
          );
        }
        if (index < row.length && row.codeUnitAt(index) != _comma) {
          throw const UafException(
            UafErrorCode.invalidCsv,
            'CSV contains characters after a closing quote.',
          );
        }
      } else {
        while (index < row.length && row.codeUnitAt(index) != _comma) {
          if (row.codeUnitAt(index) == _quote) {
            throw const UafException(
              UafErrorCode.invalidCsv,
              'CSV contains a quote in an unquoted field.',
            );
          }
          field.writeCharCode(row.codeUnitAt(index));
          index++;
        }
      }

      fields.add(field.toString());
      if (index >= row.length) break;
      index++;
      if (index == row.length) {
        fields.add('');
        break;
      }
    }
    return fields;
  }

  static Iterable<String> _tagsFromCsv(String value) sync* {
    if (value.trim().isEmpty) return;
    for (final tag in value.split(';')) {
      final trimmed = tag.trim();
      if (trimmed.isNotEmpty) yield trimmed;
    }
  }

  static const int _quote = 0x22;
  static const int _comma = 0x2c;
  static const int _lineFeed = 0x0a;
  static const int _carriageReturn = 0x0d;
}

/// TypeScript-compatible shorthand for [UafCsv.serialize].
String serializePayload(UafDocument document) => UafCsv.serialize(document);

/// TypeScript-compatible shorthand for [UafCsv.parse].
UafDocument parsePayload(String csv) => UafCsv.parse(csv);

/// Validates or defensively copies a UAF [payload].
UafDocument validatePayload(Iterable<UafAssignment> payload) {
  return payload is UafDocument ? payload : UafDocument(payload);
}
