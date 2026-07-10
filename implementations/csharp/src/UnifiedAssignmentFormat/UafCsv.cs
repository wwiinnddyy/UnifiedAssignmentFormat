using System.Text;

namespace UnifiedAssignmentFormat;

public static class UafCsv
{
    private static readonly string[] FieldNames = ["subject", "date", "content", "tags"];

    public static string Serialize(UafDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        var rows = document.Select(assignment => string.Join(",",
            EscapeField(assignment.Subject), EscapeField(assignment.Date),
            EscapeField(assignment.Content), EscapeField(string.Join(";", assignment.Tags))));
        return $"{UafConstants.CsvHeader}\n{string.Join("\n", rows)}\n";
    }

    public static byte[] SerializeToUtf8(UafDocument document) => new UTF8Encoding(false).GetBytes(Serialize(document));

    public static UafDocument Parse(string csv)
    {
        ArgumentNullException.ThrowIfNull(csv);
        var rows = SplitRows(csv.TrimStart('\uFEFF').Trim());
        if (rows.Count < 2) throw new UafException(UafErrorCode.InvalidCsv, "CSV must contain a header and at least one data row.");
        var header = ParseRow(rows[0]);
        if (!header.SequenceEqual(FieldNames, StringComparer.Ordinal)) throw new UafException(UafErrorCode.InvalidCsv, "Invalid CSV header.");
        var assignments = new List<UafAssignment>();
        for (var index = 1; index < rows.Count; index++)
        {
            var fields = ParseRow(rows[index]);
            if (fields.Count != FieldNames.Length) throw new UafException(UafErrorCode.InvalidCsv, $"Row {index + 1}: expected {FieldNames.Length} columns, got {fields.Count}.");
            try
            {
                assignments.Add(new UafAssignment(fields[0], fields[1], fields[2], TagsFromCsv(fields[3])));
            }
            catch (UafException ex)
            {
                throw new UafException(ex.Code, $"Row {index + 1}: {ex.Message}", ex);
            }
        }
        return new UafDocument(assignments);
    }

    public static UafDocument Parse(byte[] utf8Bytes) => Parse(DecodeUtf8(utf8Bytes));

    internal static string DecodeUtf8(byte[] bytes)
    {
        try { return new UTF8Encoding(false, true).GetString(bytes); }
        catch (DecoderFallbackException ex) { throw new UafException(UafErrorCode.InvalidCsv, "CSV must be valid UTF-8.", ex); }
    }

    private static string EscapeField(string value) => value.IndexOfAny(['"', ',', '\n', '\r']) < 0
        ? value
        : $"\"{value.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";

    private static List<string> SplitRows(string text)
    {
        var rows = new List<string>(); var row = new StringBuilder(); var quoted = false;
        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            if (ch == '"')
            {
                if (quoted && i + 1 < text.Length && text[i + 1] == '"') { row.Append("\"\""); i++; continue; }
                quoted = !quoted; row.Append(ch); continue;
            }
            if (!quoted && (ch == '\n' || ch == '\r'))
            {
                if (ch == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
                if (row.ToString().Trim().Length > 0) rows.Add(row.ToString());
                row.Clear(); continue;
            }
            row.Append(ch);
        }
        if (quoted) throw new UafException(UafErrorCode.InvalidCsv, "CSV contains an unterminated quoted field.");
        if (row.ToString().Trim().Length > 0) rows.Add(row.ToString());
        return rows;
    }

    private static List<string> ParseRow(string row)
    {
        var fields = new List<string>(); var field = new StringBuilder(); var quoted = false;
        for (var i = 0; i < row.Length; i++)
        {
            var ch = row[i];
            if (quoted)
            {
                if (ch == '"') { if (i + 1 < row.Length && row[i + 1] == '"') { field.Append('"'); i++; } else quoted = false; }
                else field.Append(ch);
            }
            else if (ch == '"') quoted = true;
            else if (ch == ',') { fields.Add(field.ToString()); field.Clear(); }
            else field.Append(ch);
        }
        if (quoted) throw new UafException(UafErrorCode.InvalidCsv, "CSV contains an unterminated quoted field.");
        fields.Add(field.ToString()); return fields;
    }

    private static string[] TagsFromCsv(string value) => string.IsNullOrWhiteSpace(value)
        ? []
        : value.Split(';', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
}
