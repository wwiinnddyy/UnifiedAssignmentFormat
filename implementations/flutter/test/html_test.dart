import 'package:test/test.dart';
import 'package:unified_assignment_format/unified_assignment_format.dart';

import 'test_data.dart';

void main() {
  group('UAF HTML', () {
    test('renders a self-contained document and restores its payload', () {
      final document = sampleDocument();
      final html = UafHtml.render(document);

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(RegExp('<article class="card">').allMatches(html), hasLength(3));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
      for (final requiredCss in const <String>[
        '@page { size: A4 portrait; margin: 0; }',
        'grid-template-columns: repeat(2, minmax(0, 1fr));',
        'gap: 14pt;',
        'padding: 40pt;',
        'padding: 24pt;',
        'font-size: 22pt;',
        'line-height: 1.5;',
        'font-size: 11pt;',
        'padding: 5pt 10pt;',
        'grid-template-columns: repeat(2, minmax(0, 1fr));',
        'max-width: 100%;',
        'overflow-wrap: anywhere;',
        'position: fixed;',
        'right: 40pt;',
        'bottom: 40pt;',
        'font-size: 10pt;',
      ]) {
        expect(html, contains(requiredCss));
      }
      expect(
        html,
        contains(
          '<header class="header">\n'
          '    <span class="subject-pill">',
        ),
      );
      expect(html, contains('<span class="date-pill">'));
      expect(UafHtml.extractPayload(html), document);

      final validation = UafHtml.validate(html);
      expect(validation.valid, isTrue);
      expect(validation.payload, document);
      expect(validation.errors, isEmpty);
    });

    test('escapes content, formats dates, and supports ISO display', () {
      final document = UafDocument(<UafAssignment>[
        UafAssignment(
          subject: '<数学 & 实践>',
          date: '2026-05-09T08:30:00+08:00',
          content: '比较 1 < 2 & "引用"',
          tags: const <String>["老师's"],
        ),
      ]);

      final zh = UafHtml.render(document);
      expect(zh, contains('&lt;数学 &amp; 实践&gt;'));
      expect(zh, contains('2026年5月9日'));
      expect(zh, contains('比较 1 &lt; 2 &amp; &quot;引用&quot;'));
      expect(UafHtml.extractPayload(zh), document);

      final iso = UafHtml.render(
        document,
        options: const UafHtmlRenderOptions(dateDisplay: UafDateDisplay.iso),
      );
      expect(iso, contains('2026-05-09T08:30:00+08:00'));
    });

    test('splits long content without losing payload or repeating tags', () {
      final lineSuffix = List<String>.filled(12, '长').join();
      final content = List<String>.generate(
        80,
        (index) => '第$index行$lineSuffix',
      ).join('\n');
      final document = UafDocument(<UafAssignment>[
        UafAssignment(
          subject: '语文',
          date: '2026-05-19',
          content: content,
          tags: const <String>['长文'],
        ),
      ]);
      final html = UafHtml.render(document);
      final cards = RegExp(
        r'<article class="card">([\s\S]*?)</article>',
      ).allMatches(html).toList();
      final renderedContent = RegExp(r'<div class="content">([\s\S]*?)</div>')
          .allMatches(html)
          .map((match) => match.group(1)!)
          .join()
          .replaceAll('<br>', '\n');

      expect(cards.length, greaterThan(3));
      expect(html, contains('语文（续）'));
      expect(RegExp('class="tags"').allMatches(html), hasLength(1));
      expect(renderedContent, content);
      for (final card in cards.take(cards.length - 1)) {
        expect(card.group(1), isNot(contains('class="tags"')));
      }
      expect(cards.last.group(1), contains('class="tags"'));
      expect(UafHtml.extractPayload(html), document);
    });

    test('splits twenty tags into lossless two-row continuation cards', () {
      final tags = List<String>.generate(
        20,
        (int index) => '标签${index.toString().padLeft(2, '0')}较长文本',
      );
      final document = UafDocument(<UafAssignment>[
        UafAssignment(
          subject: '综合实践',
          date: '2026-05-19',
          content: '完成项目记录。',
          tags: tags,
        ),
      ]);

      final html = UafHtml.render(document);
      final cards = RegExp(
        r'<article class="card">([\s\S]*?)</article>',
      ).allMatches(html).toList();
      final tagContainers = RegExp(
        r'<div class="tags">([\s\S]*?)</div>',
      ).allMatches(html).toList();
      final renderedTags = <String>[
        for (final card in cards)
          for (final tag in RegExp(
            r'<span class="tag-chip">([^<]*)</span>',
          ).allMatches(card.group(1)!))
            tag.group(1)!,
      ];

      expect(cards, hasLength(5));
      expect(tagContainers, hasLength(5));
      for (final container in tagContainers) {
        expect(
          RegExp('class="tag-chip"').allMatches(container.group(1)!),
          hasLength(4),
        );
      }
      expect(renderedTags, orderedEquals(tags));
      expect(RegExp('标签下页继续').allMatches(html), hasLength(4));
      expect(html, contains('综合实践（续）'));
      expect(UafHtml.extractPayload(html), document);
      expect(UafHtml.validate(html).valid, isTrue);

      final tooManyTagsInOneCard = html.replaceFirst(
        '<div class="tags">',
        '<div class="tags"><span class="tag-chip">额外标签</span>',
      );
      expect(UafHtml.validate(tooManyTagsInOneCard).valid, isFalse);
    });

    test('rejects missing required structure', () {
      final html = UafHtml.render(sampleDocument());
      final invalidVariants = <String>[
        html.replaceAll('class="document"', 'class="other-document"'),
        html.replaceAll('class="card"', 'class="other-card"'),
        html.replaceAll('class="header"', 'class="other-header"'),
      ];

      for (final invalidHtml in invalidVariants) {
        expect(UafHtml.validate(invalidHtml).valid, isFalse);
      }
    });

    test('reports missing payload and rejects external dependencies', () {
      expect(
        () => UafHtml.extractPayload('<!DOCTYPE html><html></html>'),
        throwsUaf(UafErrorCode.noPayload),
      );

      final html = UafHtml.render(sampleDocument());
      final forbidden = <String>[
        '<style>@import "https://example.com/a.css";</style>',
        '<style>.remote { background: url(https://example.com/a.png); }</style>',
        '<div style="background: url(https://example.com/a.png)"></div>',
        '<link rel="stylesheet" href="https://example.com/a.css">',
        '<script src="https://example.com/a.js"></script>',
        '<iframe src="https://example.com/"></iframe>',
        '<object data="https://example.com/a.pdf"></object>',
        '<embed src="https://example.com/a.pdf">',
        '<img src="https://example.com/a.png">',
        '<source srcset="https://example.com/a.png 1x">',
      ];

      for (final element in forbidden) {
        final invalidHtml = html.replaceFirst('</body>', '$element</body>');
        final validation = UafHtml.validate(invalidHtml);
        expect(validation.valid, isFalse, reason: element);
        expect(
          validation.errors.join(' '),
          contains('self-contained'),
          reason: element,
        );
      }
    });

    test('rejects hidden content, event handlers, and active elements', () {
      final html = UafHtml.render(sampleDocument());
      final forgedVisibleContent = html.replaceFirst(
        '<div class="content">',
        '<div class="content">伪造的可见正文：',
      );
      final forgedValidation = UafHtml.validate(forgedVisibleContent);
      expect(forgedValidation.valid, isFalse);
      expect(
        forgedValidation.errors.join(' '),
        contains('visible card content'),
      );

      final invalidVariants = <String>[
        html.replaceFirst('<body>', '<body onload="alert(1)">'),
        html.replaceFirst(
          '<main class="document">',
          '<main class="document" hidden>',
        ),
        html.replaceFirst(
          '<main class="document">',
          '<main class="document" style="display: none">',
        ),
        html.replaceFirst(
          '<main class="document">',
          '<main class="document" style="visibility: hidden">',
        ),
        html.replaceFirst(
          '</body>',
          '<div onclick="alert(1)">active</div></body>',
        ),
        html.replaceFirst(
          '</body>',
          '<form action="https://example.com/"><input></form></body>',
        ),
        html.replaceFirst(
          '</body>',
          '<svg><use href="https://example.com/icons.svg#x"></use></svg>'
              '</body>',
        ),
        html.replaceFirst(
          '</head>',
          '<meta http-equiv="refresh" content="0;url=https://example.com/">'
              '</head>',
        ),
        html.replaceFirst(
          '</style>',
          r'.remote { background: u\72l(https://example.com/a.png); }'
              '</style>',
        ),
      ];

      for (final invalidHtml in invalidVariants) {
        expect(UafHtml.validate(invalidHtml).valid, isFalse);
      }
    });
  });
}
