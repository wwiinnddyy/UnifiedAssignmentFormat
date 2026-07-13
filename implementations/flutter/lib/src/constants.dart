/// Constants defined by the Unified Assignment Format (UAF) v1.0 standard.
abstract final class UafConstants {
  /// The UAF standard version implemented by this package.
  static const String version = '1.0';

  /// The required name of the machine-readable CSV payload.
  static const String payloadFileName = 'uaf_payload.csv';

  /// The conventional artifact manifest file name.
  static const String manifestFileName = 'uaf-manifest.json';

  /// The conventional self-contained HTML display file name.
  static const String displayFileName = 'display.html';

  /// The conventional exchange PDF file name.
  static const String exchangePdfFileName = 'document.pdf';

  /// The exact, ordered header required by a UAF CSV payload.
  static const String csvHeader = 'subject,date,content,tags';

  /// The exact, ordered field names required by a UAF CSV payload.
  static const List<String> fieldNames = <String>[
    'subject',
    'date',
    'content',
    'tags',
  ];

  /// Maximum number of UTF-16 code units allowed in [UafAssignment.subject].
  static const int subjectMaxLength = 200;

  /// Maximum number of UTF-16 code units allowed in [UafAssignment.content].
  static const int contentMaxLength = 2000;

  /// Maximum number of UTF-16 code units allowed in one tag.
  static const int tagMaxLength = 50;

  /// Maximum number of tags allowed on one assignment.
  static const int tagMaxCount = 20;
}
