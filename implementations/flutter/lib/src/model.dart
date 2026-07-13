import 'dart:collection';

import 'constants.dart';
import 'errors.dart';

/// One immutable assignment record in a UAF document.
///
/// Construction validates every field against the UAF v1.0 schema. The
/// supplied [tags] iterable is copied, so later changes to the caller's
/// collection cannot mutate this assignment.
final class UafAssignment {
  /// Creates and validates an assignment.
  UafAssignment({
    required String subject,
    required String date,
    required String content,
    Iterable<String> tags = const <String>[],
  }) : subject = _requireText(
         subject,
         'subject',
         UafConstants.subjectMaxLength,
       ),
       date = _validateDate(date),
       content = _requireText(
         content,
         'content',
         UafConstants.contentMaxLength,
       ),
       tags = _validateTags(tags);

  /// The non-empty assignment subject, at most 200 characters.
  final String subject;

  /// The original, valid ISO 8601 date or date-time string.
  final String date;

  /// The non-empty assignment body, at most 2000 characters.
  final String content;

  /// An unmodifiable, ordered list of validated tags.
  final List<String> tags;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UafAssignment &&
            subject == other.subject &&
            date == other.date &&
            content == other.content &&
            _listEquals(tags, other.tags);
  }

  @override
  int get hashCode => Object.hash(subject, date, content, Object.hashAll(tags));

  @override
  String toString() {
    return 'UafAssignment(subject: $subject, date: $date, '
        'content: $content, tags: $tags)';
  }

  static String _requireText(String value, String fieldName, int maxLength) {
    if (value.isEmpty) {
      throw UafException(
        UafErrorCode.invalidPayload,
        '$fieldName must not be empty.',
      );
    }
    if (value.length > maxLength) {
      throw UafException(
        UafErrorCode.invalidPayload,
        '$fieldName must be at most $maxLength characters.',
      );
    }
    return value;
  }

  static String _validateDate(String value) {
    _requireText(value, 'date', 0x7fffffff);
    if (!_isValidIso8601(value)) {
      throw const UafException(
        UafErrorCode.invalidPayload,
        'date must be valid ISO 8601.',
      );
    }
    return value;
  }

  static List<String> _validateTags(Iterable<String> source) {
    final values = List<String>.of(source, growable: false);
    if (values.length > UafConstants.tagMaxCount) {
      throw UafException(
        UafErrorCode.invalidPayload,
        'at most ${UafConstants.tagMaxCount} tags allowed.',
      );
    }
    for (final tag in values) {
      if (tag.isEmpty) {
        throw const UafException(
          UafErrorCode.invalidPayload,
          'tag must not be empty.',
        );
      }
      if (tag.length > UafConstants.tagMaxLength) {
        throw UafException(
          UafErrorCode.invalidPayload,
          'each tag must be at most ${UafConstants.tagMaxLength} characters.',
        );
      }
      if (tag.contains(';')) {
        throw const UafException(
          UafErrorCode.invalidPayload,
          'tag must not contain ";".',
        );
      }
    }
    return List<String>.unmodifiable(values);
  }

  static bool _isValidIso8601(String value) {
    final match = _iso8601Pattern.firstMatch(value);
    if (match == null) return false;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > _daysInMonth(year, month)) return false;

    final hourText = match.group(4);
    if (hourText == null) return true;
    final hour = int.parse(hourText);
    final minute = int.parse(match.group(5)!);
    final secondText = match.group(6);
    if (hour > 23 || minute > 59) return false;
    if (secondText != null && int.parse(secondText) > 59) return false;

    final offsetHourText = match.group(8);
    if (offsetHourText != null) {
      final offsetHour = int.parse(offsetHourText);
      final offsetMinute = int.parse(match.group(9) ?? '0');
      if (offsetHour > 23 || offsetMinute > 59) return false;
    }
    return true;
  }

  static int _daysInMonth(int year, int month) {
    const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month != 2) return days[month - 1];
    final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return leap ? 29 : 28;
  }

  static final RegExp _iso8601Pattern = RegExp(
    r'^([+-]?\d{4,6})-(\d{2})-(\d{2})'
    r'(?:[Tt ](\d{2}):(\d{2})'
    r'(?::(\d{2})(?:[.,](\d{1,9}))?)?'
    r'(?:[Zz]|[+-](\d{2})(?::?(\d{2}))?)?)?$',
  );
}

/// An immutable, non-empty, ordered UAF assignment collection.
///
/// [UafDocument] implements the read side of Dart's [List] API for convenient
/// indexing and iteration. Every mutating list operation throws
/// [UnsupportedError].
final class UafDocument extends ListBase<UafAssignment> {
  /// Creates a document and defensively copies [assignments].
  UafDocument(Iterable<UafAssignment> assignments)
    : _assignments = List<UafAssignment>.unmodifiable(assignments) {
    if (_assignments.isEmpty) {
      throw const UafException(
        UafErrorCode.invalidPayload,
        'document must contain at least one assignment.',
      );
    }
  }

  final List<UafAssignment> _assignments;

  /// The assignments as an unmodifiable list.
  List<UafAssignment> get assignments => _assignments;

  @override
  int get length => _assignments.length;

  @override
  set length(int value) {
    throw UnsupportedError('UafDocument is immutable.');
  }

  @override
  UafAssignment operator [](int index) => _assignments[index];

  @override
  void operator []=(int index, UafAssignment value) {
    throw UnsupportedError('UafDocument is immutable.');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UafDocument && _listEquals(_assignments, other._assignments);
  }

  @override
  int get hashCode => Object.hashAll(_assignments);

  @override
  String toString() => 'UafDocument($_assignments)';
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
