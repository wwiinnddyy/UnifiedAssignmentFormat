using System.Collections.ObjectModel;
using System.Globalization;

namespace UnifiedAssignmentFormat;

public sealed class UafAssignment : IEquatable<UafAssignment>
{
    private readonly string[] _tags;
    private readonly ReadOnlyCollection<string> _readOnlyTags;

    public UafAssignment(string subject, string date, string content, IEnumerable<string>? tags = null)
    {
        Subject = RequireText(subject, nameof(subject), UafConstants.SubjectMaxLength);
        Date = ValidateDate(date);
        Content = RequireText(content, nameof(content), UafConstants.ContentMaxLength);
        _tags = ValidateTags(tags ?? []);
        _readOnlyTags = Array.AsReadOnly(_tags);
    }

    public string Subject { get; }
    public string Date { get; }
    public string Content { get; }
    public IReadOnlyList<string> Tags => _readOnlyTags;

    public bool Equals(UafAssignment? other) => other is not null
        && StringComparer.Ordinal.Equals(Subject, other.Subject)
        && StringComparer.Ordinal.Equals(Date, other.Date)
        && StringComparer.Ordinal.Equals(Content, other.Content)
        && _tags.SequenceEqual(other._tags, StringComparer.Ordinal);

    public override bool Equals(object? obj) => obj is UafAssignment other && Equals(other);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(Subject, StringComparer.Ordinal);
        hash.Add(Date, StringComparer.Ordinal);
        hash.Add(Content, StringComparer.Ordinal);
        foreach (var tag in _tags) hash.Add(tag, StringComparer.Ordinal);
        return hash.ToHashCode();
    }

    private static string RequireText(string value, string fieldName, int maxLength)
    {
        if (string.IsNullOrEmpty(value)) throw new UafException(UafErrorCode.InvalidPayload, $"{fieldName} must not be empty.");
        if (value.Length > maxLength) throw new UafException(UafErrorCode.InvalidPayload, $"{fieldName} must be at most {maxLength} characters.");
        return value;
    }

    private static string ValidateDate(string value)
    {
        RequireText(value, nameof(Date), int.MaxValue);
        if (DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _)
            || DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out _)) return value;
        throw new UafException(UafErrorCode.InvalidPayload, "date must be valid ISO 8601.");
    }

    private static string[] ValidateTags(IEnumerable<string> tags)
    {
        var values = tags.ToArray();
        if (values.Length > UafConstants.TagMaxCount) throw new UafException(UafErrorCode.InvalidPayload, $"at most {UafConstants.TagMaxCount} tags allowed.");
        foreach (var tag in values)
        {
            if (string.IsNullOrEmpty(tag)) throw new UafException(UafErrorCode.InvalidPayload, "tag must not be empty.");
            if (tag.Length > UafConstants.TagMaxLength) throw new UafException(UafErrorCode.InvalidPayload, $"each tag must be at most {UafConstants.TagMaxLength} characters.");
            if (tag.Contains(';', StringComparison.Ordinal)) throw new UafException(UafErrorCode.InvalidPayload, "tag must not contain \";\".");
        }
        return values;
    }
}
