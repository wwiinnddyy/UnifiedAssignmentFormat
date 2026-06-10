using System.Text;

namespace UnifiedAssignmentFormat;

public static class UafCsv
{
    private static readonly string[] FieldNames = ["subject", "date", "content", "tags"];

    public static string Serialize(UafPayload payload)
    {
        ArgumentNullException.ThrowIfNull(payload);

        var row = string.Join(
            ",",
            EscapeField(payload.Subject),
            EscapeField(payload.Date),
            EscapeField(payload.Content),
            EscapeField(string.Join(";", payload.Tags)));

        return $"{UafConstants.CsvHeader}\n{row}\n";
    }

    public static byte[] SerializeToUtf8(UafPayload payload)
    {
        return new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(Serialize(payload));
    }

    public static UafPayload Parse(string csv)
    {
        if (csv is null)
        {
            throw new ArgumentNullException(nameof(csv));
        }

        var normalized = csv.TrimStart('\uFEFF').Trim();
        var rows = SplitRows(normalized);

        if (rows.Count < 2)
        {
            throw new UafException(
                UafErrorCode.InvalidCsv,
                "CSV must contain header and exactly one data row.");
        }

        if (rows.Count > 2)
        {
            throw new UafException(UafErrorCode.InvalidCsv, "CSV must contain exactly one data row.");
        }

        var headerFields = ParseRow(rows[0]);
        if (!headerFields.SequenceEqual(FieldNames, StringComparer.Ordinal))
        {
            throw new UafException(
                UafErrorCode.InvalidCsv,
                $"Invalid header: expected \"{UafConstants.CsvHeader}\", got \"{string.Join(",", headerFields)}\".");
        }

        var dataFields = ParseRow(rows[1]);
        if (dataFields.Count != FieldNames.Length)
        {
            throw new UafException(
                UafErrorCode.InvalidCsv,
                $"Expected {FieldNames.Length} columns, got {dataFields.Count}.");
        }

        return new UafPayload(
            dataFields[0],
            dataFields[1],
            dataFields[2],
            TagsFromCsv(dataFields[3]));
    }

    public static UafPayload Parse(byte[] utf8Bytes)
    {
        ArgumentNullException.ThrowIfNull(utf8Bytes);
        return Parse(DecodeUtf8(utf8Bytes));
    }

    internal static string DecodeUtf8(byte[] bytes)
    {
        try
        {
            return new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                .GetString(bytes);
        }
        catch (DecoderFallbackException ex)
        {
            throw new UafException(UafErrorCode.InvalidCsv, "CSV must be valid UTF-8.", ex);
        }
    }

    private static string EscapeField(string value)
    {
        if (value.IndexOfAny(['"', ',', '\n', '\r']) < 0)
        {
            return value;
        }

        return $"\"{value.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
    }

    private static List<string> SplitRows(string text)
    {
        var rows = new List<string>();
        var row = new StringBuilder();
        var inQuotes = false;

        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];

            if (ch == '"')
            {
                if (inQuotes && i + 1 < text.Length && text[i + 1] == '"')
                {
                    row.Append(ch);
                    row.Append(text[i + 1]);
                    i++;
                    continue;
                }

                inQuotes = !inQuotes;
                row.Append(ch);
                continue;
            }

            if (!inQuotes && (ch == '\n' || ch == '\r'))
            {
                if (ch == '\r' && i + 1 < text.Length && text[i + 1] == '\n')
                {
                    i++;
                }

                AddNonEmptyRow(rows, row);
                continue;
            }

            row.Append(ch);
        }

        if (inQuotes)
        {
            throw new UafException(UafErrorCode.InvalidCsv, "CSV contains an unterminated quoted field.");
        }

        AddNonEmptyRow(rows, row);
        return rows;
    }

    private static void AddNonEmptyRow(List<string> rows, StringBuilder row)
    {
        if (row.ToString().Trim().Length > 0)
        {
            rows.Add(row.ToString());
        }

        row.Clear();
    }

    private static List<string> ParseRow(string row)
    {
        var fields = new List<string>();
        var field = new StringBuilder();
        var inQuotes = false;
        var quotedField = false;
        var afterClosingQuote = false;

        for (var i = 0; i < row.Length; i++)
        {
            var ch = row[i];

            if (inQuotes)
            {
                if (ch == '"')
                {
                    if (i + 1 < row.Length && row[i + 1] == '"')
                    {
                        field.Append('"');
                        i++;
                        continue;
                    }

                    inQuotes = false;
                    afterClosingQuote = true;
                    continue;
                }

                field.Append(ch);
                continue;
            }

            if (ch == ',')
            {
                fields.Add(field.ToString());
                field.Clear();
                quotedField = false;
                afterClosingQuote = false;
                continue;
            }

            if (ch == '"')
            {
                if (field.Length > 0 || afterClosingQuote)
                {
                    throw new UafException(UafErrorCode.InvalidCsv, "Unexpected quote in CSV field.");
                }

                quotedField = true;
                inQuotes = true;
                continue;
            }

            if (afterClosingQuote && !char.IsWhiteSpace(ch))
            {
                throw new UafException(UafErrorCode.InvalidCsv, "Unexpected characters after quoted CSV field.");
            }

            if (!quotedField || !char.IsWhiteSpace(ch))
            {
                field.Append(ch);
            }
        }

        if (inQuotes)
        {
            throw new UafException(UafErrorCode.InvalidCsv, "CSV contains an unterminated quoted field.");
        }

        fields.Add(field.ToString());
        return fields;
    }

    private static string[] TagsFromCsv(string tagsColumn)
    {
        if (string.IsNullOrWhiteSpace(tagsColumn))
        {
            return [];
        }

        return tagsColumn
            .Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
    }
}
