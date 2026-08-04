using System.Globalization;
using System.Net;
using System.Text.RegularExpressions;

namespace UnifiedAssignmentFormat;

public enum UafDateDisplay { Zh, Iso }
public sealed record UafHtmlRenderOptions { public UafDateDisplay DateDisplay { get; init; } = UafDateDisplay.Zh; }

public static partial class UafHtml
{
    public static string Render(UafDocument document, UafHtmlRenderOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(document);
        options ??= new UafHtmlRenderOptions();
        var cards = document.SelectMany(assignment => SplitContent(assignment.Content).Select((content, index) =>
            RenderCard(assignment, content, index, SplitContent(assignment.Content).Count, options.DateDisplay)));
        var csv = WebUtility.HtmlEncode(UafCsv.Serialize(document));
        return $$"""
<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8"><title>UAF - 作业</title>
<style>
@page { size: A4 portrait; margin: 36pt 36pt 58pt; }
@media print { body { margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; } .watermark { position: fixed; } }
* { box-sizing: border-box; } html, body { margin: 0; padding: 0; }
body { background:#F8FAFC; color:#0F172A; font-family:"Noto Sans SC","Microsoft YaHei",sans-serif; }
.document { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:14pt; align-items:start; }
.card { break-inside:avoid; background:#FFF; border:1pt solid #E2E8F0; border-radius:16pt; overflow:hidden; }
.header { background:#2563EB; padding:12pt 14pt; }.subject { color:#FFF; font-size:17pt; font-weight:600; }.date { color:#DBEAFE; font-size:9.5pt; }
.content { padding:16pt 14pt 12pt; font-size:13.5pt; line-height:1.42; overflow-wrap:anywhere; }
.tags { display:flex; flex-wrap:wrap; gap:6pt; padding:0 14pt 14pt; }.tag { background:#E0E7FF;color:#3730A3;font-size:9.5pt;padding:4pt 8pt;border-radius:9999pt; }
.continued { color:#64748B;font-size:9.5pt;padding:0 14pt 14pt; }.watermark { right:36pt;bottom:30pt;color:#94A3B8;font-size:9pt;opacity:.65; }
</style></head><body><main class="document">{{string.Join("\n", cards)}}</main>
<div class="watermark">本文件符合UAF标准规范</div>
<template id="uaf-payload-csv" data-filename="uaf_payload.csv">{{csv}}</template></body></html>
""";
    }

    public static string ExtractPayloadCsv(string html)
    {
        ArgumentNullException.ThrowIfNull(html);
        var match = PayloadTemplateRegex().Match(html);
        if (!match.Success) throw new UafException(UafErrorCode.NoPayload, "HTML does not contain a uaf-payload-csv template.");
        return WebUtility.HtmlDecode(match.Groups[2].Value);
    }

    public static UafDocument ExtractPayload(string html) => UafCsv.Parse(ExtractPayloadCsv(html));

    private static List<string> SplitContent(string content, int limit = 520)
    {
        var normalized = content.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        var chunks = new List<string>();
        for (var index = 0; index < normalized.Length; index += limit) chunks.Add(normalized.Substring(index, Math.Min(limit, normalized.Length - index)));
        return chunks.Count > 0 ? chunks : [""];
    }

    private static string RenderCard(UafAssignment assignment, string content, int index, int total, UafDateDisplay display)
    {
        var subject = WebUtility.HtmlEncode(assignment.Subject) + (index > 0 ? "（续）" : "");
        var date = WebUtility.HtmlEncode(FormatDate(assignment.Date, display));
        var body = string.Join("<br>", content.Split('\n').Select(WebUtility.HtmlEncode));
        var footer = index == total - 1
            ? $"<div class=\"tags\">{string.Join("", assignment.Tags.Select(tag => $"<span class=\"tag\">{WebUtility.HtmlEncode(tag)}</span>"))}</div>"
            : "<div class=\"continued\">正文下页继续</div>";
        return $"<article class=\"card\"><header class=\"header\"><div class=\"subject\">{subject}</div><div class=\"date\">{date}</div></header><div class=\"content\">{body}</div>{footer}</article>";
    }

    private static string FormatDate(string value, UafDateDisplay display)
    {
        if (display == UafDateDisplay.Iso) return value;
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
            ? $"{date.Year}年{date.Month}月{date.Day}日" : value;
    }

    [GeneratedRegex("<template\\b(?=[^>]*\\bid=([\\\"'])uaf-payload-csv\\1)[^>]*>([\\s\\S]*?)</template>", RegexOptions.IgnoreCase)]
    private static partial Regex PayloadTemplateRegex();
}
