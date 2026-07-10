using System.Globalization;
using System.IO.Compression;
using System.Text;

namespace UnifiedAssignmentFormat;

public static class UafPdf
{
    private const double PageWidth = 595.28;
    private const double PageHeight = 841.89;
    private static readonly byte[] PdfHeader = Encoding.ASCII.GetBytes("%PDF-");

    public static byte[] Create(UafDocument payload)
    {
        ArgumentNullException.ThrowIfNull(payload);

        var csvBytes = UafCsv.SerializeToUtf8(payload);
        var fileNameUtf16Hex = ToUtf16Hex(UafConstants.PayloadFileName);
        var fragments = ExpandAssignments(payload);
        var pageGroups = fragments.Chunk(4).ToArray();
        var fontObject = 3 + pageGroups.Length * 2;
        var cidObject = fontObject + 1;
        var embeddedObject = fontObject + 2;
        var fileSpecObject = fontObject + 3;
        var descriptorObject = fontObject + 4;
        var kids = string.Join(" ", Enumerable.Range(0, pageGroups.Length).Select(i => $"{3 + i * 2} 0 R"));
        var objects = new List<byte[]>
        {
            Obj($"<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [(uaf_payload.csv) {fileSpecObject} 0 R] >> >> /AF [{fileSpecObject} 0 R] >>"),
            Obj($"<< /Type /Pages /Count {pageGroups.Length} /Kids [{kids}] >>")
        };
        for (var index = 0; index < pageGroups.Length; index++)
        {
            var contentBytes = Encoding.ASCII.GetBytes(RenderGridPage(pageGroups[index]));
            var contentObject = 4 + index * 2;
            objects.Add(Obj($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 {fontObject} 0 R >> >> /Contents {contentObject} 0 R >>"));
            objects.Add(StreamObj("<< /Length " + contentBytes.Length.ToString(CultureInfo.InvariantCulture) + " >>", contentBytes));
        }
        objects.Add(Obj($"<< /Type /Font /Subtype /Type0 /BaseFont /STSong-Light /Encoding /UniGB-UCS2-H /DescendantFonts [{cidObject} 0 R] >>"));
        objects.Add(Obj($"<< /Type /Font /Subtype /CIDFontType0 /BaseFont /STSong-Light /CIDSystemInfo << /Registry (Adobe) /Ordering (GB1) /Supplement 2 >> /FontDescriptor {descriptorObject} 0 R >>"));
        objects.Add(StreamObj("<< /Type /EmbeddedFile /Subtype /text#2Fcsv /Params << /Size " + csvBytes.Length.ToString(CultureInfo.InvariantCulture) + " >> /Length " + csvBytes.Length.ToString(CultureInfo.InvariantCulture) + " >>", csvBytes));
        objects.Add(Obj($"<< /Type /Filespec /F (uaf_payload.csv) /UF <{fileNameUtf16Hex}> /Desc (UAF v1.0 multi-assignment payload) /AFRelationship /Data /EF << /F {embeddedObject} 0 R /UF {embeddedObject} 0 R >> >>"));
        objects.Add(Obj("<< /Type /FontDescriptor /FontName /STSong-Light /Flags 4 /FontBBox [-200 -250 1000 880] /ItalicAngle 0 /Ascent 880 /Descent -120 /CapHeight 700 /StemV 80 >>"));

        return WritePdf(objects);
    }

    public static UafDocument ExtractPayload(byte[] pdfBytes)
    {
        return UafCsv.Parse(ExtractPayloadCsv(pdfBytes));
    }

    public static string ExtractPayloadCsv(byte[] pdfBytes)
    {
        var csv = TryExtractPayloadCsv(pdfBytes);
        if (csv is null)
        {
            throw new UafException(
                UafErrorCode.NoPayload,
                $"Embedded file \"{UafConstants.PayloadFileName}\" not found.");
        }

        return csv;
    }

    public static string? TryExtractPayloadCsv(byte[] pdfBytes)
    {
        ArgumentNullException.ThrowIfNull(pdfBytes);

        if (!StartsWith(pdfBytes, PdfHeader))
        {
            throw new UafException(UafErrorCode.CorruptPdf, "PDF bytes do not start with a PDF header.");
        }

        var direct = TryFindCsv(pdfBytes);
        if (direct is not null)
        {
            return direct;
        }

        foreach (var stream in EnumerateStreams(pdfBytes))
        {
            var csv = TryFindCsv(stream);
            if (csv is not null)
            {
                return csv;
            }

            foreach (var inflated in InflateCandidates(stream))
            {
                csv = TryFindCsv(inflated);
                if (csv is not null)
                {
                    return csv;
                }
            }
        }

        return null;
    }

    private static byte[] WritePdf(IReadOnlyList<byte[]> objects)
    {
        using var output = new MemoryStream();
        WriteAscii(output, "%PDF-1.7\n%\u00E2\u00E3\u00CF\u00D3\n");

        var offsets = new long[objects.Count + 1];
        for (var i = 0; i < objects.Count; i++)
        {
            offsets[i + 1] = output.Position;
            WriteAscii(output, $"{i + 1} 0 obj\n");
            output.Write(objects[i]);
            WriteAscii(output, "\nendobj\n");
        }

        var xrefOffset = output.Position;
        WriteAscii(output, $"xref\n0 {objects.Count + 1}\n");
        WriteAscii(output, "0000000000 65535 f \n");
        for (var i = 1; i < offsets.Length; i++)
        {
            WriteAscii(output, $"{offsets[i]:0000000000} 00000 n \n");
        }

        WriteAscii(
            output,
            $"trailer\n<< /Size {objects.Count + 1} /Root 1 0 R >>\nstartxref\n{xrefOffset}\n%%EOF\n");

        return output.ToArray();
    }

    private static IReadOnlyList<UafAssignment> ExpandAssignments(UafDocument document)
    {
        var fragments = new List<UafAssignment>();
        foreach (var assignment in document)
        {
            const int limit = 420;
            for (var index = 0; index < assignment.Content.Length; index += limit)
            {
                var content = assignment.Content.Substring(index, Math.Min(limit, assignment.Content.Length - index));
                var final = index + limit >= assignment.Content.Length;
                fragments.Add(new UafAssignment(
                    assignment.Subject + (index > 0 ? "（续）" : string.Empty),
                    assignment.Date,
                    content,
                    final ? assignment.Tags : []));
            }
        }
        return fragments;
    }

    private static string RenderGridPage(IReadOnlyList<UafAssignment> assignments)
    {
        const double margin = 36;
        const double gap = 14;
        const double cardWidth = (PageWidth - margin * 2 - gap) / 2;
        const double cardHeight = 340;
        var builder = new StringBuilder();
        builder.AppendLine("q 0.973 0.980 0.988 rg 0 0 595.28 841.89 re f Q");
        for (var index = 0; index < assignments.Count; index++)
        {
            var assignment = assignments[index];
            var column = index % 2;
            var row = index / 2;
            var x = margin + column * (cardWidth + gap);
            var y = PageHeight - margin - cardHeight - row * (cardHeight + gap);
            builder.AppendLine("q 0.80 0.84 0.89 rg");
            builder.AppendLine(RoundedRectPath(x + 2, y - 2, cardWidth, cardHeight, 12));
            builder.AppendLine("f Q q 1 1 1 rg");
            builder.AppendLine(RoundedRectPath(x, y, cardWidth, cardHeight, 12));
            builder.AppendLine("f Q q 0.145 0.388 0.922 rg");
            builder.AppendLine(RoundedRectPath(x, y + cardHeight - 52, cardWidth, 52, 12));
            builder.AppendLine("f Q");
            AppendText(builder, assignment.Subject, x + 14, y + cardHeight - 25, 17, "#FFFFFF");
            AppendText(builder, FormatDateZh(assignment.Date), x + 14, y + cardHeight - 42, 9.5, "#DBEAFE");
            var layout = FitContent(assignment.Content, cardWidth - 28, cardHeight - 102);
            var lineY = y + cardHeight - 76;
            foreach (var line in layout.Lines)
            {
                AppendText(builder, line, x + 14, lineY, layout.FontSize, "#0F172A");
                lineY -= layout.LineHeight;
            }
            var tagX = x + 14;
            foreach (var tag in assignment.Tags.Take(4))
            {
                var tagWidth = Math.Min(EstimateTextWidth(tag, 9.5) + 16, cardWidth - 28);
                builder.AppendLine("q 0.878 0.906 1 rg");
                builder.AppendLine(RoundedRectPath(tagX, y + 13, tagWidth, 19, 9.5));
                builder.AppendLine("f Q");
                AppendText(builder, tag, tagX + 8, y + 18, 9.5, "#3730A3");
                tagX += tagWidth + 6;
                if (tagX > x + cardWidth - 30) break;
            }
        }
        const string watermark = "使用 UAF v1.0 导出";
        AppendText(builder, watermark, PageWidth - margin - EstimateTextWidth(watermark, 9), margin - 4, 9, "#94A3B8");
        return builder.ToString();
    }

    private static string RenderPageContent(UafAssignment payload)
    {
        const double margin = 40;
        const double cardX = margin;
        const double cardWidth = PageWidth - (margin * 2);
        const double padding = 24;
        const double subjectFont = 14;
        const double dateFont = 12;
        const double tagFont = 11;
        const double watermarkFont = 10;

        var dateText = FormatDateZh(payload.Date);
        var subjectPillWidth = Math.Min(EstimateTextWidth(payload.Subject, subjectFont) + 32, cardWidth * 0.64);
        var datePillWidth = EstimateTextWidth(dateText, dateFont) + 24;
        var contentLayout = FitContent(payload.Content, cardWidth - (padding * 2), PageHeight - 170);
        var tagRows = LayoutTags(payload.Tags, cardWidth - (padding * 2), tagFont);

        var tagHeight = tagRows.Count == 0 ? 0 : (tagRows.Count * 21) + ((tagRows.Count - 1) * 8) + 20;
        var cardHeight = padding + 30 + 16 + 1 + 20 + contentLayout.Lines.Count * contentLayout.LineHeight + tagHeight + padding;
        cardHeight = Math.Min(cardHeight, PageHeight - 120);

        var cardY = PageHeight - margin - cardHeight;
        var contentTop = PageHeight - margin - padding - 30 - 16 - 1 - 20;
        var contentBaseline = contentTop - contentLayout.FontSize;

        var builder = new StringBuilder();
        builder.AppendLine("q");
        builder.AppendLine("0.973 0.980 0.988 rg");
        builder.AppendLine($"0 0 {F(PageWidth)} {F(PageHeight)} re f");
        builder.AppendLine("Q");

        builder.AppendLine("q");
        builder.AppendLine("0.580 0.639 0.722 rg");
        builder.AppendLine(RoundedRectPath(cardX + 2, cardY - 2, cardWidth, cardHeight, 16));
        builder.AppendLine("f");
        builder.AppendLine("Q");

        builder.AppendLine("q");
        builder.AppendLine("1 1 1 rg");
        builder.AppendLine(RoundedRectPath(cardX, cardY, cardWidth, cardHeight, 16));
        builder.AppendLine("f");
        builder.AppendLine("0.886 0.910 0.941 RG 1 w");
        builder.AppendLine(RoundedRectPath(cardX, cardY, cardWidth, cardHeight, 16));
        builder.AppendLine("S");
        builder.AppendLine("Q");

        var headerTop = PageHeight - margin - padding;
        var pillY = headerTop - 30;
        builder.AppendLine("q");
        builder.AppendLine("0.145 0.388 0.922 rg");
        builder.AppendLine(RoundedRectPath(cardX + padding, pillY, subjectPillWidth, 30, 15));
        builder.AppendLine("f");
        builder.AppendLine("Q");
        AppendText(builder, payload.Subject, cardX + padding + 16, pillY + 9, subjectFont, "#FFFFFF");

        builder.AppendLine("q");
        builder.AppendLine("0.945 0.961 0.976 rg");
        builder.AppendLine(RoundedRectPath(cardX + cardWidth - padding - datePillWidth, pillY + 3, datePillWidth, 24, 12));
        builder.AppendLine("f");
        builder.AppendLine("Q");
        AppendText(builder, dateText, cardX + cardWidth - padding - datePillWidth + 12, pillY + 10, dateFont, "#334155");

        var dividerY = PageHeight - margin - padding - 30 - 16;
        builder.AppendLine("q");
        builder.AppendLine("0.886 0.910 0.941 rg");
        builder.AppendLine($"{F(cardX + padding)} {F(dividerY)} {F(cardWidth - padding * 2)} 1 re f");
        builder.AppendLine("Q");

        foreach (var line in contentLayout.Lines)
        {
            AppendText(builder, line, cardX + padding, contentBaseline, contentLayout.FontSize, "#0F172A");
            contentBaseline -= contentLayout.LineHeight;
        }

        var tagY = contentBaseline - 4;
        foreach (var row in tagRows)
        {
            var tagX = cardX + padding;
            foreach (var tag in row)
            {
                var width = EstimateTextWidth(tag, tagFont) + 20;
                builder.AppendLine("q");
                builder.AppendLine("0.878 0.906 1 rg");
                builder.AppendLine(RoundedRectPath(tagX, tagY, width, 21, 10.5));
                builder.AppendLine("f");
                builder.AppendLine("Q");
                AppendText(builder, tag, tagX + 10, tagY + 6, tagFont, "#3730A3");
                tagX += width + 8;
            }

            tagY -= 29;
        }

        const string watermark = "使用 UAF v1.0 导出";
        AppendText(
            builder,
            watermark,
            PageWidth - margin - EstimateTextWidth(watermark, watermarkFont),
            margin,
            watermarkFont,
            "#94A3B8");

        return builder.ToString();
    }

    private static ContentLayout FitContent(string content, double width, double maxHeight)
    {
        foreach (var size in new[] { 22d, 18d, 16d, 14d })
        {
            var lines = WrapContent(content, width, size);
            var lineHeight = size * 1.5;
            if (lines.Count * lineHeight <= maxHeight)
            {
                return new ContentLayout(size, lineHeight, lines);
            }
        }

        var finalLines = WrapContent(content, width, 14);
        var maxLines = Math.Max(1, (int)Math.Floor(maxHeight / (14 * 1.5)));
        if (finalLines.Count > maxLines)
        {
            finalLines = finalLines.Take(maxLines).ToList();
            var last = finalLines[^1];
            finalLines[^1] = last.Length == 0 ? "..." : last[..Math.Max(0, last.Length - 1)] + "...";
        }

        return new ContentLayout(14, 21, finalLines);
    }

    private static List<string> WrapContent(string content, double width, double fontSize)
    {
        var lines = new List<string>();
        foreach (var paragraph in content.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n'))
        {
            var current = new StringBuilder();
            var currentWidth = 0d;

            foreach (var rune in paragraph.EnumerateRunes())
            {
                var text = rune.ToString();
                var runeWidth = EstimateTextWidth(text, fontSize);
                if (current.Length > 0 && currentWidth + runeWidth > width)
                {
                    lines.Add(current.ToString());
                    current.Clear();
                    currentWidth = 0;
                }

                current.Append(text);
                currentWidth += runeWidth;
            }

            lines.Add(current.ToString());
        }

        return lines;
    }

    private static List<List<string>> LayoutTags(IReadOnlyList<string> tags, double width, double fontSize)
    {
        var rows = new List<List<string>>();
        if (tags.Count == 0)
        {
            return rows;
        }

        var current = new List<string>();
        var currentWidth = 0d;

        foreach (var tag in tags)
        {
            var tagWidth = EstimateTextWidth(tag, fontSize) + 20;
            var nextWidth = current.Count == 0 ? tagWidth : currentWidth + 8 + tagWidth;
            if (current.Count > 0 && nextWidth > width)
            {
                rows.Add(current);
                if (rows.Count == 2)
                {
                    return rows;
                }

                current = [];
                currentWidth = 0;
            }

            current.Add(tag);
            currentWidth = current.Count == 1 ? tagWidth : currentWidth + 8 + tagWidth;
        }

        if (current.Count > 0 && rows.Count < 2)
        {
            rows.Add(current);
        }

        return rows;
    }

    private static void AppendText(StringBuilder builder, string text, double x, double y, double size, string color)
    {
        var (r, g, b) = HexColor(color);
        builder.AppendLine("BT");
        builder.AppendLine($"/F1 {F(size)} Tf");
        builder.AppendLine($"{F(r)} {F(g)} {F(b)} rg");
        builder.AppendLine($"1 0 0 1 {F(x)} {F(y)} Tm");
        builder.AppendLine($"<{ToUtf16Hex(text)}> Tj");
        builder.AppendLine("ET");
    }

    private static string RoundedRectPath(double x, double y, double width, double height, double radius)
    {
        var k = radius * 0.5522847498;
        var right = x + width;
        var top = y + height;

        return string.Join(
            "\n",
            $"{F(x + radius)} {F(y)} m",
            $"{F(right - radius)} {F(y)} l",
            $"{F(right - radius + k)} {F(y)} {F(right)} {F(y + radius - k)} {F(right)} {F(y + radius)} c",
            $"{F(right)} {F(top - radius)} l",
            $"{F(right)} {F(top - radius + k)} {F(right - radius + k)} {F(top)} {F(right - radius)} {F(top)} c",
            $"{F(x + radius)} {F(top)} l",
            $"{F(x + radius - k)} {F(top)} {F(x)} {F(top - radius + k)} {F(x)} {F(top - radius)} c",
            $"{F(x)} {F(y + radius)} l",
            $"{F(x)} {F(y + radius - k)} {F(x + radius - k)} {F(y)} {F(x + radius)} {F(y)} c",
            "h");
    }

    private static double EstimateTextWidth(string text, double size)
    {
        var units = 0d;
        foreach (var rune in text.EnumerateRunes())
        {
            units += rune.Value <= 0x007F ? 0.55 : 1.0;
        }

        return units * size;
    }

    private static string FormatDateZh(string date)
    {
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

    private static IEnumerable<byte[]> EnumerateStreams(byte[] pdfBytes)
    {
        var streamMarker = Encoding.ASCII.GetBytes("stream");
        var endStreamMarker = Encoding.ASCII.GetBytes("endstream");
        var index = 0;

        while (true)
        {
            var streamIndex = IndexOf(pdfBytes, streamMarker, index);
            if (streamIndex < 0)
            {
                yield break;
            }

            var dataStart = streamIndex + streamMarker.Length;
            if (dataStart < pdfBytes.Length && pdfBytes[dataStart] == '\r')
            {
                dataStart++;
            }

            if (dataStart < pdfBytes.Length && pdfBytes[dataStart] == '\n')
            {
                dataStart++;
            }

            var dataEnd = IndexOf(pdfBytes, endStreamMarker, dataStart);
            if (dataEnd < 0)
            {
                yield break;
            }

            while (dataEnd > dataStart && (pdfBytes[dataEnd - 1] == '\n' || pdfBytes[dataEnd - 1] == '\r'))
            {
                dataEnd--;
            }

            var length = dataEnd - dataStart;
            if (length > 0)
            {
                var stream = new byte[length];
                Buffer.BlockCopy(pdfBytes, dataStart, stream, 0, length);
                yield return stream;
            }

            index = dataEnd + endStreamMarker.Length;
        }
    }

    private static IEnumerable<byte[]> InflateCandidates(byte[] bytes)
    {
        var zlib = TryInflate(bytes, useZlib: true);
        if (zlib is not null)
        {
            yield return zlib;
        }

        var deflate = TryInflate(bytes, useZlib: false);
        if (deflate is not null)
        {
            yield return deflate;
        }
    }

    private static byte[]? TryInflate(byte[] bytes, bool useZlib)
    {
        try
        {
            using var input = new MemoryStream(bytes);
            using Stream inflater = useZlib
                ? new ZLibStream(input, CompressionMode.Decompress)
                : new DeflateStream(input, CompressionMode.Decompress);
            using var output = new MemoryStream();
            inflater.CopyTo(output);
            return output.Length == 0 ? null : output.ToArray();
        }
        catch (InvalidDataException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    private static string? TryFindCsv(byte[] bytes)
    {
        string text;
        try
        {
            text = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                .GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return null;
        }

        var index = text.IndexOf(UafConstants.CsvHeader, StringComparison.Ordinal);
        if (index < 0)
        {
            return null;
        }

        var candidate = text[index..].Trim('\0', '\t', '\r', '\n', ' ');
        try
        {
            _ = UafCsv.Parse(candidate);
            return candidate.EndsWith('\n') ? candidate : candidate + "\n";
        }
        catch (UafException)
        {
            return null;
        }
    }

    private static int IndexOf(byte[] haystack, byte[] needle, int start)
    {
        for (var i = start; i <= haystack.Length - needle.Length; i++)
        {
            var match = true;
            for (var j = 0; j < needle.Length; j++)
            {
                if (haystack[i + j] != needle[j])
                {
                    match = false;
                    break;
                }
            }

            if (match)
            {
                return i;
            }
        }

        return -1;
    }

    private static bool StartsWith(byte[] haystack, byte[] needle)
    {
        return haystack.Length >= needle.Length && haystack.AsSpan(0, needle.Length).SequenceEqual(needle);
    }

    private static byte[] Obj(string value)
    {
        return Encoding.ASCII.GetBytes(value);
    }

    private static byte[] StreamObj(string dictionary, byte[] stream)
    {
        using var output = new MemoryStream();
        WriteAscii(output, dictionary);
        WriteAscii(output, "\nstream\n");
        output.Write(stream);
        WriteAscii(output, "\nendstream");
        return output.ToArray();
    }

    private static void WriteAscii(Stream stream, string value)
    {
        var bytes = Encoding.ASCII.GetBytes(value);
        stream.Write(bytes);
    }

    private static string ToUtf16Hex(string value)
    {
        var bytes = Encoding.BigEndianUnicode.GetBytes(value);
        return Convert.ToHexString(bytes);
    }

    private static string F(double value)
    {
        return value.ToString("0.###", CultureInfo.InvariantCulture);
    }

    private static (double R, double G, double B) HexColor(string hex)
    {
        var value = hex.TrimStart('#');
        return (
            int.Parse(value.AsSpan(0, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture) / 255d,
            int.Parse(value.AsSpan(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture) / 255d,
            int.Parse(value.AsSpan(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture) / 255d);
    }

    private sealed record ContentLayout(double FontSize, double LineHeight, List<string> Lines);
}
