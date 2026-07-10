using System.Collections;
using System.Collections.ObjectModel;

namespace UnifiedAssignmentFormat;

public sealed class UafDocument : IReadOnlyList<UafAssignment>, IEquatable<UafDocument>
{
    private readonly ReadOnlyCollection<UafAssignment> _assignments;

    public UafDocument(IEnumerable<UafAssignment> assignments)
    {
        ArgumentNullException.ThrowIfNull(assignments);
        var values = assignments.ToArray();
        if (values.Length == 0) throw new UafException(UafErrorCode.InvalidPayload, "document must contain at least one assignment.");
        if (values.Any(value => value is null)) throw new UafException(UafErrorCode.InvalidPayload, "document assignments must not be null.");
        _assignments = Array.AsReadOnly(values);
    }

    public int Count => _assignments.Count;
    public UafAssignment this[int index] => _assignments[index];
    public IEnumerator<UafAssignment> GetEnumerator() => _assignments.GetEnumerator();
    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
    public bool Equals(UafDocument? other) => other is not null && _assignments.SequenceEqual(other._assignments);
    public override bool Equals(object? obj) => obj is UafDocument other && Equals(other);
    public override int GetHashCode() => _assignments.Aggregate(17, (hash, item) => HashCode.Combine(hash, item));

    internal static void EnsureSame(string sourceName, UafDocument expected, UafDocument actual)
    {
        if (!expected.Equals(actual)) throw new UafException(UafErrorCode.InvalidPackage, $"{sourceName} payload does not match the canonical CSV payload.");
    }
}
