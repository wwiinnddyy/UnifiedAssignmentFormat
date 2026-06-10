using System.Globalization;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace UnifiedAssignmentFormat;

public enum UafDateDisplay
{
    Zh,
    Iso
}

public sealed record UafHtmlRenderOptions
{
    public UafDateDisplay DateDisplay { get; init; } = UafDateDisplay.Zh;
}

public static partial class UafHtml
{
    public static string Render(UafPayload payload, UafHtmlRenderOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(payload);

        options ??= new UafHtmlRenderOptions();
        var subject = EscapeHtml(payload.Subject);
        var date = EscapeHtml(FormatDate(payload.Date, options.DateDisplay));
        var content = RenderContent(payload.Content);
        var tags = RenderTags(payload.Tags);
        var csv = EscapeHtml(UafCsv.Serialize(payload));

        return $$"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UAF - {{subject}}</title>
<style>
@page {
  size: A4 portrait;
  margin: 0;
}

@media print {
  body {
    margin: 0;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
}

* {
  box-sizing: border-box;
}

html, body {
  margin: 0;
  padding: 0;
}

body {
  width: 210mm;
  min-height: 297mm;
  background: #F8FAFC;
  font-family: "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "Hiragino Sans GB", "WenQuanYi Micro Hei", sans-serif;
  color: #0F172A;
  position: relative;
  padding: 40pt;
}

.card {
  background: #FFFFFF;
  border: 1pt solid #E2E8F0;
  border-radius: 16pt;
  box-shadow: 0 2pt 8pt rgba(148, 163, 184, 0.15);
  width: 100%;
  padding: 24pt;
}

.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16pt;
  margin-bottom: 16pt;
}

.subject-pill {
  display: inline-block;
  background: #2563EB;
  color: #FFFFFF;
  font-size: 14pt;
  line-height: 1;
  padding: 8pt 16pt;
  border-radius: 9999pt;
  font-weight: 600;
  max-width: 70%;
  overflow-wrap: anywhere;
}

.date-pill {
  display: inline-block;
  background: #F1F5F9;
  color: #334155;
  font-size: 12pt;
  line-height: 1;
  padding: 6pt 12pt;
  border-radius: 9999pt;
  white-space: nowrap;
}

.divider {
  height: 1pt;
  background: #E2E8F0;
  margin-bottom: 20pt;
}

.content {
  font-size: 22pt;
  line-height: 1.5;
  color: #0F172A;
  overflow-wrap: anywhere;
}

.tags {
  display: flex;
  flex-wrap: wrap;
  gap: 8pt;
  margin-top: 20pt;
}

.tag-chip {
  display: inline-block;
  background: #E0E7FF;
  color: #3730A3;
  font-size: 11pt;
  line-height: 1;
  padding: 5pt 10pt;
  border-radius: 9999pt;
}

.watermark {
  position: absolute;
  right: 40pt;
  bottom: 40pt;
  font-size: 10pt;
  color: #94A3B8;
  opacity: 0.5;
  pointer-events: none;
  user-select: none;
}
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <span class="subject-pill">{{subject}}</span>
    <span class="date-pill">{{date}}</span>
  </div>
  <div class="divider"></div>
  <div class="content">{{content}}</div>
  {{tags}}
</div>
<div class="watermark">使用 UAF v1.0 导出</div>
<template id="uaf-payload-csv" data-filename="uaf_payload.csv">{{csv}}</template>
</body>
</html>
""";
    }

    public static UafPayload ExtractPayload(string html)
    {
        return UafCsv.Parse(ExtractPayloadCsv(html));
    }

    public static string ExtractPayloadCsv(string html)
    {
        if (html is null)
        {
            throw new ArgumentNullException(nameof(html));
        }

        var match = PayloadTemplateRegex().Match(html);
        if (!match.Success)
        {
            throw new UafException(
                UafErrorCode.InvalidHtml,
                "HTML must contain template#uaf-payload-csv with data-filename=\"uaf_payload.csv\".");
        }

        return WebUtility.HtmlDecode(match.Groups["csv"].Value);
    }

    private static string FormatDate(string date, UafDateDisplay display)
    {
        if (display == UafDateDisplay.Iso)
        {
            return date;
        }

        if (DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var dateOnly))
        {
            return $"{dateOnly.Year}年{dateOnly.Month}月{dateOnly.Day}日";
        }

        if (DateTimeOffset.TryParse(date, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dateTime))
        {
            return $"{dateTime.Year}年{dateTime.Month}月{dateTime.Day}日";
        }

        return date;
    }

    private static string RenderContent(string content)
    {
        return string.Join("<br>", content.Split('\n').Select(line => EscapeHtml(line.TrimEnd('\r'))));
    }

    private static string RenderTags(IReadOnlyList<string> tags)
    {
        if (tags.Count == 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder();
        builder.Append("<div class=\"tags\">");
        foreach (var tag in tags)
        {
            builder.Append("<span class=\"tag-chip\">");
            builder.Append(EscapeHtml(tag));
            builder.Append("</span>");
        }

        builder.Append("</div>");
        return builder.ToString();
    }

    private static string EscapeHtml(string value)
    {
        return WebUtility.HtmlEncode(value);
    }

    [GeneratedRegex(
        "<template\\b(?=[^>]*\\bid\\s*=\\s*(['\"])uaf-payload-csv\\1)(?=[^>]*\\bdata-filename\\s*=\\s*(['\"])uaf_payload\\.csv\\2)[^>]*>(?<csv>.*?)</template>",
        RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.CultureInvariant)]
    private static partial Regex PayloadTemplateRegex();
}
