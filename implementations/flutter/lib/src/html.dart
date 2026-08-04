import 'dart:collection';

import 'constants.dart';
import 'csv.dart';
import 'errors.dart';
import 'model.dart';

/// Date formatting modes supported by the UAF HTML renderer.
enum UafDateDisplay {
  /// Render dates as `YYYY年M月D日`.
  zh,

  /// Preserve the original ISO 8601 value.
  iso,
}

/// Immutable options for [UafHtml.render].
final class UafHtmlRenderOptions {
  /// Creates renderer options.
  const UafHtmlRenderOptions({this.dateDisplay = UafDateDisplay.zh});

  /// Controls how assignment dates are displayed on cards.
  final UafDateDisplay dateDisplay;
}

/// The non-throwing result returned by [UafHtml.validate].
final class UafHtmlValidationResult {
  UafHtmlValidationResult._({
    required this.valid,
    required this.payload,
    required Iterable<String> errors,
  }) : errors = UnmodifiableListView<String>(List<String>.of(errors));

  /// Whether both the embedded payload and printable structure are valid.
  final bool valid;

  /// The restored payload when [valid] is true; otherwise `null`.
  final UafDocument? payload;

  /// Human-readable validation failures. Empty when [valid] is true.
  final List<String> errors;
}

/// Self-contained UAF HTML rendering, extraction, and validation.
abstract final class UafHtml {
  static const int _tagsPerCard = 4;

  /// Renders [document] as a complete, self-contained HTML5 document.
  ///
  /// The standard CSV payload is HTML-escaped into an inert
  /// `<template id="uaf-payload-csv">` element. Long bodies are split into
  /// continuation cards without modifying the embedded canonical payload.
  static String render(
    UafDocument document, {
    UafHtmlRenderOptions options = const UafHtmlRenderOptions(),
  }) {
    final cards = <String>[];
    for (final assignment in document) {
      final chunks = _splitContent(assignment.content);
      final tagGroups = _groupTags(assignment.tags);
      for (var index = 0; index < chunks.length; index++) {
        final isLastContentChunk = index == chunks.length - 1;
        cards.add(
          _renderCard(
            assignment,
            chunks[index],
            continuation: index > 0,
            tags: isLastContentChunk && tagGroups.isNotEmpty
                ? tagGroups.first
                : const <String>[],
            continuationMessage: !isLastContentChunk
                ? '正文下页继续'
                : tagGroups.length > 1
                ? '标签下页继续'
                : null,
            display: options.dateDisplay,
          ),
        );
      }
      for (var index = 1; index < tagGroups.length; index++) {
        cards.add(
          _renderCard(
            assignment,
            '',
            continuation: true,
            tags: tagGroups[index],
            continuationMessage: index < tagGroups.length - 1 ? '标签下页继续' : null,
            display: options.dateDisplay,
          ),
        );
      }
    }
    final payloadCsv = _escapeHtml(UafCsv.serialize(document));

    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UAF - 作业</title>
<style>
@page { size: A4 portrait; margin: 0; }
@media print {
  body { margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: #F8FAFC;
  color: #0F172A;
  font-family: "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "Hiragino Sans GB", "WenQuanYi Micro Hei", sans-serif;
}
.document {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14pt;
  align-items: start;
  padding: 40pt;
}
.card {
  break-inside: avoid;
  page-break-inside: avoid;
  background: #FFFFFF;
  border: 1pt solid #E2E8F0;
  border-radius: 16pt;
  box-shadow: 0 2pt 8pt rgba(148, 163, 184, 0.15);
  padding: 24pt;
  overflow: hidden;
}
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12pt;
  padding-bottom: 20pt;
  border-bottom: 1pt solid #E2E8F0;
}
.subject-pill {
  display: inline-block;
  min-width: 0;
  background: #2563EB;
  color: #FFFFFF;
  font-size: 14pt;
  line-height: 1.2;
  padding: 8pt 16pt;
  border-radius: 9999pt;
  overflow-wrap: anywhere;
}
.date-pill {
  display: inline-block;
  flex: 0 0 auto;
  background: #F1F5F9;
  color: #334155;
  font-size: 12pt;
  line-height: 1.2;
  padding: 6pt 12pt;
  border-radius: 9999pt;
  white-space: nowrap;
}
.content {
  margin-top: 20pt;
  color: #0F172A;
  font-size: 22pt;
  line-height: 1.5;
  text-align: left;
  overflow-wrap: anywhere;
}
.tags {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8pt;
  margin-top: 20pt;
}
.tag-chip {
  justify-self: start;
  min-width: 0;
  max-width: 100%;
  background: #E0E7FF;
  color: #3730A3;
  font-size: 11pt;
  padding: 5pt 10pt;
  border-radius: 9999pt;
  overflow-wrap: anywhere;
}
.continued { color: #64748B; font-size: 11pt; margin-top: 20pt; }
.watermark {
  position: fixed;
  right: 40pt;
  bottom: 40pt;
  color: #94A3B8;
  opacity: 0.5;
  font-size: 10pt;
  pointer-events: none;
}
</style>
</head>
<body>
<main class="document">${cards.join('\n')}</main>
<div class="watermark">本文件符合UAF标准规范</div>
<template id="uaf-payload-csv" data-filename="${UafConstants.payloadFileName}">$payloadCsv</template>
</body>
</html>''';
  }

  /// Extracts and HTML-decodes the embedded canonical CSV payload.
  ///
  /// Throws [UafException] with [UafErrorCode.noPayload] when the required
  /// template is absent.
  static String extractPayloadCsv(String html) {
    final match = _payloadTemplatePattern.firstMatch(html);
    if (match == null) {
      throw const UafException(
        UafErrorCode.noPayload,
        'HTML does not contain a uaf-payload-csv template.',
      );
    }
    return _decodeHtmlEntities(match.group(2)!);
  }

  /// Restores and validates the UAF document embedded in [html].
  static UafDocument extractPayload(String html) {
    return UafCsv.parse(extractPayloadCsv(html));
  }

  /// Validates the embedded payload and required self-contained print markup.
  ///
  /// This method never throws for malformed HTML; failures are accumulated in
  /// [UafHtmlValidationResult.errors].
  static UafHtmlValidationResult validate(String html) {
    final errors = <String>[];
    UafDocument? payload;
    try {
      payload = extractPayload(html);
    } on UafException catch (error) {
      errors.add(error.message);
    } on Object catch (error) {
      errors.add('Unknown HTML validation error: $error');
    }

    errors.addAll(_validatePrintableStructure(html));
    if (payload != null && !_visibleCardsMatchPayload(html, payload)) {
      errors.add(
        'HTML visible card content does not match its embedded UAF payload',
      );
    }
    if (errors.isNotEmpty) {
      return UafHtmlValidationResult._(
        valid: false,
        payload: null,
        errors: errors,
      );
    }
    return UafHtmlValidationResult._(
      valid: true,
      payload: payload,
      errors: const <String>[],
    );
  }

  /// Validates [html] and returns its payload, or throws `INVALID_HTML`.
  static UafDocument validateOrThrow(String html) {
    final result = validate(html);
    if (!result.valid) {
      throw UafException(UafErrorCode.invalidHtml, result.errors.join('; '));
    }
    return result.payload!;
  }

  static List<String> _splitContent(
    String content, [
    int limit = 150,
    int maxLineBreaks = 14,
  ]) {
    final normalized = content.replaceAll(RegExp(r'\r\n?'), '\n');
    final chunks = <String>[];
    var cursor = 0;
    while (cursor < normalized.length) {
      var end = cursor + limit;
      if (end > normalized.length) end = normalized.length;
      end = _avoidSplittingSurrogatePair(normalized, cursor, end);
      var endedAtLineLimit = false;
      var lineBreaks = 0;
      for (var index = cursor; index < end; index++) {
        if (normalized.codeUnitAt(index) != _lineFeed) continue;
        lineBreaks++;
        if (lineBreaks == maxLineBreaks) {
          end = index + 1;
          endedAtLineLimit = true;
          break;
        }
      }
      if (!endedAtLineLimit && end < normalized.length) {
        final breakAt = normalized.lastIndexOf('\n', end - 1);
        if (breakAt > cursor + limit ~/ 2) end = breakAt + 1;
      }
      chunks.add(normalized.substring(cursor, end));
      cursor = end;
    }
    return chunks.isEmpty ? const <String>[''] : chunks;
  }

  static int _avoidSplittingSurrogatePair(String text, int cursor, int end) {
    if (end <= cursor || end >= text.length) return end;
    final previous = text.codeUnitAt(end - 1);
    final next = text.codeUnitAt(end);
    final previousIsHigh = previous >= 0xd800 && previous <= 0xdbff;
    final nextIsLow = next >= 0xdc00 && next <= 0xdfff;
    return previousIsHigh && nextIsLow ? end - 1 : end;
  }

  static String _renderCard(
    UafAssignment assignment,
    String content, {
    required bool continuation,
    required List<String> tags,
    required String? continuationMessage,
    required UafDateDisplay display,
  }) {
    final continuationSuffix = continuation ? '（续）' : '';
    final subject = '${_escapeHtml(assignment.subject)}$continuationSuffix';
    final date = _escapeHtml(_formatDate(assignment.date, display));
    final body = content.split('\n').map(_escapeHtml).join('<br>');

    final footer = StringBuffer();
    if (tags.isNotEmpty) {
      final renderedTags = tags
          .map((tag) => '<span class="tag-chip">${_escapeHtml(tag)}</span>')
          .join();
      footer.write('\n  <div class="tags">$renderedTags</div>');
    }
    if (continuationMessage != null) {
      footer.write(
        '\n  <div class="continued">${_escapeHtml(continuationMessage)}</div>',
      );
    }

    return '''<article class="card">
  <header class="header">
    <span class="subject-pill">$subject</span>
    <span class="date-pill">$date</span>
  </header>
  <div class="content">$body</div>$footer
</article>''';
  }

  static List<List<String>> _groupTags(List<String> tags) {
    if (tags.isEmpty) return const <List<String>>[];
    return <List<String>>[
      for (var index = 0; index < tags.length; index += _tagsPerCard)
        List<String>.unmodifiable(
          tags.sublist(
            index,
            index + _tagsPerCard < tags.length
                ? index + _tagsPerCard
                : tags.length,
          ),
        ),
    ];
  }

  static String _formatDate(String value, UafDateDisplay display) {
    if (display == UafDateDisplay.iso) return value;
    final match = _datePrefixPattern.firstMatch(value);
    if (match == null) return value;
    final year = match.group(1)!;
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    return '$year年$month月$day日';
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _decodeHtmlEntities(String text) {
    return text.replaceAllMapped(_htmlEntityPattern, (match) {
      final entity = match.group(1)!;
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        return _decodeNumericEntity(entity.substring(2), 16, match.group(0)!);
      }
      if (entity.startsWith('#')) {
        return _decodeNumericEntity(entity.substring(1), 10, match.group(0)!);
      }
      return switch (entity.toLowerCase()) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => '\u00a0',
        _ => match.group(0)!,
      };
    });
  }

  static String _decodeNumericEntity(String digits, int radix, String source) {
    final value = int.tryParse(digits, radix: radix);
    if (value == null ||
        value <= 0 ||
        value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff)) {
      return source;
    }
    return String.fromCharCode(value);
  }

  static List<String> _validatePrintableStructure(String html) {
    final errors = <String>[..._validateElementSafety(html)];
    if (!_doctypePattern.hasMatch(html)) {
      errors.add('HTML must start with an HTML5 doctype');
    }
    if (!_htmlElementPattern.hasMatch(html) ||
        !_headElementPattern.hasMatch(html) ||
        !_bodyElementPattern.hasMatch(html)) {
      errors.add('HTML must be a complete HTML5 document');
    }
    final styleMatches = _styleContentPattern.allMatches(html).toList();
    if (styleMatches.isEmpty) {
      errors.add('HTML must inline its print CSS in a style tag');
    } else {
      final css = styleMatches.map((match) => match.group(1)!).join('\n');
      if (!_atPagePattern.hasMatch(css)) {
        errors.add('HTML must define @page print CSS');
      }
      if (!_printColorPattern.hasMatch(css)) {
        errors.add(
          'HTML print CSS must preserve background colors when printed',
        );
      }
      if (_containsForbiddenCss(html, styleMatches)) {
        errors.add('HTML must stay self-contained without CSS imports or URLs');
      }
      if (_containsHiddenCss(html, styleMatches)) {
        errors.add('HTML must not hide UAF content with CSS');
      }
    }
    if (!_hasElementWithClass(html, 'main', 'document')) {
      errors.add('HTML must contain the UAF document element');
    }
    final articles = _articleElementPattern.allMatches(html).toList();
    final cards = articles
        .where((article) => _openingTagHasClass(article.group(1)!, 'card'))
        .toList();
    if (cards.isEmpty) {
      errors.add('HTML must contain at least one UAF card');
    } else {
      if (articles.length != cards.length) {
        errors.add('Every assignment article must use the UAF card class');
      }
      for (final card in cards) {
        final cardHtml = card.group(2)!;
        if (!_hasElementWithClass(cardHtml, 'header', 'header')) {
          errors.add('Every UAF card must contain a header');
          break;
        }
        final tagCount = _spanElementPattern
            .allMatches(cardHtml)
            .where((span) => _openingTagHasClass(span.group(1)!, 'tag-chip'))
            .length;
        if (tagCount > _tagsPerCard) {
          errors.add(
            'Every UAF card may contain at most $_tagsPerCard tag chips',
          );
          break;
        }
      }
      for (final requirement in const <String, String>{
        'subject-pill': 'span',
        'date-pill': 'span',
        'content': 'div',
      }.entries) {
        if (cards.any(
          (card) => !_hasElementWithClass(
            card.group(2)!,
            requirement.value,
            requirement.key,
          ),
        )) {
          errors.add(
            'Every UAF card must contain a ${requirement.key} element',
          );
        }
      }
    }
    if (!_hasElementWithClass(html, 'div', 'watermark')) {
      errors.add('HTML must contain the fixed UAF watermark');
    } else if (!_hasStandardWatermark(html)) {
      errors.add('HTML watermark must contain the standard UAF export text');
    }
    if (!_payloadTemplateWithFilenamePattern.hasMatch(html)) {
      errors.add(
        'HTML payload template must declare '
        'data-filename="${UafConstants.payloadFileName}"',
      );
    }
    if (_externalAssetPattern.hasMatch(html)) {
      errors.add(
        'HTML must stay self-contained without active or external elements',
      );
    }
    return errors;
  }

  static List<String> _validateElementSafety(String html) {
    final errors = <String>[];
    final unsupportedTags = <String>{};
    for (final match in _allTagPattern.allMatches(html)) {
      final tag = match.group(1)!.toLowerCase();
      if (!_allowedTags.contains(tag)) unsupportedTags.add(tag);
    }
    if (unsupportedTags.isNotEmpty) {
      errors.add(
        'HTML must stay self-contained and use only inert UAF elements; '
        'unsupported: ${unsupportedTags.join(', ')}',
      );
    }

    var hasEventHandler = false;
    var hasHiddenAttribute = false;
    var hasExternalOrActiveAttribute = false;
    for (final match in _openingTagPattern.allMatches(html)) {
      final openingTag = match.group(0)!;
      hasEventHandler |= _eventAttributePattern.hasMatch(openingTag);
      hasHiddenAttribute |= _hiddenAttributePattern.hasMatch(openingTag);
      hasExternalOrActiveAttribute |= _externalOrActiveAttributePattern
          .hasMatch(openingTag);
    }
    if (hasEventHandler) {
      errors.add('HTML must not contain event-handler attributes');
    }
    if (hasHiddenAttribute) {
      errors.add('HTML must not hide UAF content with the hidden attribute');
    }
    if (hasExternalOrActiveAttribute) {
      errors.add(
        'HTML must stay self-contained without active or external-loading '
        'attributes',
      );
    }
    return errors;
  }

  static bool _visibleCardsMatchPayload(String html, UafDocument payload) {
    final actual = _cardSignatures(html);
    if (actual == null) return false;
    final expectedZh = _cardSignatures(render(payload));
    final expectedIso = _cardSignatures(
      render(
        payload,
        options: const UafHtmlRenderOptions(dateDisplay: UafDateDisplay.iso),
      ),
    );
    return expectedZh != null && _signatureListsEqual(actual, expectedZh) ||
        expectedIso != null && _signatureListsEqual(actual, expectedIso);
  }

  static List<_HtmlCardSignature>? _cardSignatures(String html) {
    final bodyMatches = _canonicalBodyPattern.allMatches(html).toList();
    if (bodyMatches.length != 1) return null;
    final mainContent = bodyMatches.single.group(1)!;
    final cardMatches = _articleElementPattern.allMatches(mainContent).toList();
    if (cardMatches.isEmpty) return null;
    if (mainContent.replaceAll(_articleElementPattern, '').trim().isNotEmpty) {
      return null;
    }

    final signatures = <_HtmlCardSignature>[];
    for (final card in cardMatches) {
      if (!_openingTagHasClass(card.group(1)!, 'card')) return null;
      final match = _canonicalCardPattern.firstMatch(card.group(2)!);
      if (match == null) return null;

      final subject = _decodeCanonicalText(match.group(1)!);
      final date = _decodeCanonicalText(match.group(2)!);
      final content = _decodeCanonicalContent(match.group(3)!);
      final continued = match.group(5) == null
          ? null
          : _decodeCanonicalText(match.group(5)!);
      if (subject == null ||
          date == null ||
          content == null ||
          (match.group(5) != null && continued == null)) {
        return null;
      }

      final tags = <String>[];
      final tagsHtml = match.group(4);
      if (tagsHtml != null) {
        final tagMatches = _canonicalTagPattern.allMatches(tagsHtml).toList();
        if (tagMatches.isEmpty ||
            tagsHtml.replaceAll(_canonicalTagPattern, '').trim().isNotEmpty) {
          return null;
        }
        for (final tag in tagMatches) {
          final decoded = _decodeCanonicalText(tag.group(1)!);
          if (decoded == null) return null;
          tags.add(decoded);
        }
      }
      signatures.add(
        _HtmlCardSignature(
          subject: subject,
          date: date,
          content: content,
          tags: tags,
          continued: continued,
        ),
      );
    }
    return signatures;
  }

  static String? _decodeCanonicalText(String html) {
    if (html.contains('<') || html.contains('>')) return null;
    return _decodeHtmlEntities(html);
  }

  static String? _decodeCanonicalContent(String html) {
    final withLineFeeds = html.replaceAll(_brPattern, '\n');
    return _decodeCanonicalText(withLineFeeds);
  }

  static bool _signatureListsEqual(
    List<_HtmlCardSignature> left,
    List<_HtmlCardSignature> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static bool _hasElementWithClass(String html, String? tag, String className) {
    final tagPattern = tag == null ? r'[a-z][a-z0-9:-]*' : RegExp.escape(tag);
    final elements = RegExp(
      '<$tagPattern\\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html);
    return elements.any(
      (element) => _openingTagHasClass(element.group(0)!, className),
    );
  }

  static bool _openingTagHasClass(String openingTag, String className) {
    final match = _classAttributePattern.firstMatch(openingTag);
    if (match == null) return false;
    final classes = (match.group(1) ?? match.group(2)!).split(RegExp(r'\s+'));
    return classes.contains(className);
  }

  static bool _hasStandardWatermark(String html) {
    for (final element in _divElementPattern.allMatches(html)) {
      if (_openingTagHasClass(element.group(1)!, 'watermark') &&
          _watermarkContentPattern.hasMatch(element.group(2)!)) {
        return true;
      }
    }
    return false;
  }

  static bool _containsForbiddenCss(
    String html,
    Iterable<RegExpMatch> styleMatches,
  ) {
    for (final match in styleMatches) {
      if (_forbiddenCssPattern.hasMatch(_withoutCssComments(match.group(1)!))) {
        return true;
      }
    }
    for (final match in _styleAttributePattern.allMatches(html)) {
      final value = match.group(1) ?? match.group(2)!;
      if (_forbiddenCssPattern.hasMatch(_withoutCssComments(value))) {
        return true;
      }
    }
    return false;
  }

  static bool _containsHiddenCss(
    String html,
    Iterable<RegExpMatch> styleMatches,
  ) {
    for (final match in styleMatches) {
      if (_hiddenCssPattern.hasMatch(_withoutCssComments(match.group(1)!))) {
        return true;
      }
    }
    for (final match in _styleAttributePattern.allMatches(html)) {
      final value = match.group(1) ?? match.group(2)!;
      if (_hiddenCssPattern.hasMatch(_withoutCssComments(value))) return true;
    }
    return false;
  }

  static String _withoutCssComments(String css) {
    return css.replaceAll(_cssCommentPattern, '');
  }

  static final RegExp _payloadTemplatePattern = RegExp(
    r'''<template\b(?=[^>]*\sid\s*=\s*(["'])uaf-payload-csv\1)[^>]*>([\s\S]*?)</template>''',
    caseSensitive: false,
  );
  static final RegExp _payloadTemplateWithFilenamePattern = RegExp(
    r'''<template\b(?=[^>]*\sid\s*=\s*(["'])uaf-payload-csv\1)(?=[^>]*\sdata-filename\s*=\s*(["'])uaf_payload\.csv\2)[^>]*>''',
    caseSensitive: false,
  );
  static final RegExp _datePrefixPattern = RegExp(
    r'^([+-]?\d{4,6})-(\d{2})-(\d{2})(?:$|[Tt ])',
  );
  static final RegExp _htmlEntityPattern = RegExp(
    r'&(#(?:[xX][0-9a-fA-F]+|\d+)|amp|lt|gt|quot|apos|nbsp);',
    caseSensitive: false,
  );
  static final RegExp _doctypePattern = RegExp(
    r'^\s*<!DOCTYPE html>',
    caseSensitive: false,
  );
  static final RegExp _htmlElementPattern = RegExp(
    r'<html\b[\s\S]*?</html>',
    caseSensitive: false,
  );
  static final RegExp _headElementPattern = RegExp(
    r'<head\b[\s\S]*?</head>',
    caseSensitive: false,
  );
  static final RegExp _bodyElementPattern = RegExp(
    r'<body\b[\s\S]*?</body>',
    caseSensitive: false,
  );
  static final RegExp _styleContentPattern = RegExp(
    r'<style\b[^>]*>([\s\S]*?)</style>',
    caseSensitive: false,
  );
  static final RegExp _articleElementPattern = RegExp(
    r'(<article\b[^>]*>)([\s\S]*?)</article>',
    caseSensitive: false,
  );
  static final RegExp _canonicalBodyPattern = RegExp(
    r'<body\s*>\s*<main\s+class="document"\s*>([\s\S]*?)</main>\s*'
    r'<div\s+class="watermark"\s*>\s*本文件符合UAF标准规范\s*'
    r'</div>\s*<template\s+id="uaf-payload-csv"\s+'
    r'data-filename="uaf_payload\.csv"\s*>[\s\S]*?</template>\s*</body>',
    caseSensitive: false,
  );
  static final RegExp _canonicalCardPattern = RegExp(
    r'^\s*<header\s+class="header"\s*>\s*'
    r'<span\s+class="subject-pill"\s*>([\s\S]*?)</span>\s*'
    r'<span\s+class="date-pill"\s*>([\s\S]*?)</span>\s*'
    r'</header>\s*<div\s+class="content"\s*>([\s\S]*?)</div>'
    r'(?:\s*<div\s+class="tags"\s*>([\s\S]*?)</div>)?'
    r'(?:\s*<div\s+class="continued"\s*>([\s\S]*?)</div>)?\s*$',
    caseSensitive: false,
  );
  static final RegExp _canonicalTagPattern = RegExp(
    r'\s*<span\s+class="tag-chip"\s*>([\s\S]*?)</span>\s*',
    caseSensitive: false,
  );
  static final RegExp _brPattern = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final RegExp _divElementPattern = RegExp(
    r'(<div\b[^>]*>)([\s\S]*?)</div>',
    caseSensitive: false,
  );
  static final RegExp _spanElementPattern = RegExp(
    r'(<span\b[^>]*>)([\s\S]*?)</span>',
    caseSensitive: false,
  );
  static final RegExp _watermarkContentPattern = RegExp(
    r'^\s*本文件符合UAF标准规范\s*$',
    caseSensitive: false,
  );
  static final RegExp _classAttributePattern = RegExp(
    r'''\sclass\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );
  static final RegExp _atPagePattern = RegExp(
    r'@page\b',
    caseSensitive: false,
  );
  static final RegExp _printColorPattern = RegExp(
    r'print-color-adjust\s*:\s*exact',
    caseSensitive: false,
  );
  static final RegExp _styleAttributePattern = RegExp(
    r'''\sstyle\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );
  static final RegExp _forbiddenCssPattern = RegExp(
    r'@\s*import\b|url\s*\(|image-set\s*\(|@\s*font-face\b|'
    r'-moz-binding\s*:|behavior\s*:|expression\s*\(|\\',
    caseSensitive: false,
  );
  static final RegExp _hiddenCssPattern = RegExp(
    r'(?:^|[;{])\s*(?:display\s*:\s*none|visibility\s*:\s*hidden|'
    r'content-visibility\s*:\s*hidden)',
    caseSensitive: false,
  );
  static final RegExp _cssCommentPattern = RegExp(r'/\*[\s\S]*?\*/');
  static final RegExp _externalAssetPattern = RegExp(
    r'<\s*(?:link|script|iframe|object|embed)\b|'
    r'<[^>]*\s(?:src|srcset)\s*=',
    caseSensitive: false,
  );
  static final RegExp _allTagPattern = RegExp(
    r'<\s*/?\s*([a-z][a-z0-9:-]*)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _openingTagPattern = RegExp(
    r'<\s*([a-z][a-z0-9:-]*)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _eventAttributePattern = RegExp(
    r'\son[a-z0-9_:-]+\s*=',
    caseSensitive: false,
  );
  static final RegExp _hiddenAttributePattern = RegExp(
    r'''\shidden(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?(?=\s|/?>)''',
    caseSensitive: false,
  );
  static final RegExp _externalOrActiveAttributePattern = RegExp(
    r'\s(?:href|src|srcset|action|formaction|poster|background|data|ping|'
    r'manifest|xlink:href|http-equiv|shadowrootmode)\s*=',
    caseSensitive: false,
  );
  static const Set<String> _allowedTags = <String>{
    'html',
    'head',
    'meta',
    'title',
    'style',
    'body',
    'main',
    'article',
    'header',
    'span',
    'div',
    'br',
    'template',
  };
  static const int _lineFeed = 0x0a;
}

final class _HtmlCardSignature {
  _HtmlCardSignature({
    required this.subject,
    required this.date,
    required this.content,
    required List<String> tags,
    required this.continued,
  }) : tags = List<String>.unmodifiable(tags);

  final String subject;
  final String date;
  final String content;
  final List<String> tags;
  final String? continued;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _HtmlCardSignature &&
            subject == other.subject &&
            date == other.date &&
            content == other.content &&
            _stringListsEqual(tags, other.tags) &&
            continued == other.continued;
  }

  @override
  int get hashCode =>
      Object.hash(subject, date, content, Object.hashAll(tags), continued);
}

bool _stringListsEqual(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// TypeScript-compatible shorthand for [UafHtml.render].
String renderUafHtml(
  UafDocument document, {
  UafHtmlRenderOptions options = const UafHtmlRenderOptions(),
}) => UafHtml.render(document, options: options);

/// TypeScript-compatible shorthand for [UafHtml.extractPayloadCsv].
String extractUafPayloadCsvFromHtml(String html) {
  return UafHtml.extractPayloadCsv(html);
}

/// TypeScript-compatible shorthand for [UafHtml.extractPayload].
UafDocument extractUafPayloadFromHtml(String html) {
  return UafHtml.extractPayload(html);
}

/// TypeScript-compatible shorthand for [UafHtml.validate].
UafHtmlValidationResult validateUafHtml(String html) => UafHtml.validate(html);
