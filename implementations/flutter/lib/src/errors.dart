/// Stable error categories reported by the UAF implementation.
enum UafErrorCode {
  /// The CSV bytes or RFC 4180 structure are invalid.
  invalidCsv('INVALID_CSV'),

  /// A document or assignment violates the UAF schema.
  invalidPayload('INVALID_PAYLOAD'),

  /// A carrier does not contain the required UAF payload.
  noPayload('NO_PAYLOAD'),

  /// A PDF cannot be decoded or has an invalid structure.
  corruptPdf('CORRUPT_PDF'),

  /// An HTML document violates the UAF HTML requirements.
  invalidHtml('INVALID_HTML'),

  /// An integrated UAF artifact package is invalid.
  invalidPackage('INVALID_PACKAGE'),

  /// An artifact does not match its declared digest.
  hashMismatch('HASH_MISMATCH');

  const UafErrorCode(this.value);

  /// The language-neutral, upper-snake-case representation of this code.
  final String value;

  @override
  String toString() => value;
}

/// An exception with a stable [code] suitable for programmatic handling.
final class UafException implements Exception {
  /// Creates a UAF exception.
  const UafException(
    this.code,
    this.message, [
    this.cause,
    this.causeStackTrace,
  ]);

  /// The machine-readable category of the failure.
  final UafErrorCode code;

  /// A human-readable explanation of the failure.
  final String message;

  /// The lower-level error, when this exception wraps another failure.
  final Object? cause;

  /// The stack trace associated with [cause], when available.
  final StackTrace? causeStackTrace;

  @override
  String toString() => 'UafException(${code.value}): $message';
}

/// TypeScript-compatible shorthand for [UafException].
typedef UafError = UafException;
