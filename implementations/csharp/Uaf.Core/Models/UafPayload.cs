using Uaf.Core.Helpers;

namespace Uaf.Core.Models;

public sealed record UafPayload
{
    public required string Subject { get; init; }
    public required string Date { get; init; }
    public required string Content { get; set; }
    public required IReadOnlyList<string> Tags { get; set; }

    public UafPayload()
    {
        if (string.IsNullOrEmpty(Subject) || Subject.Length > 200)
            throw new ArgumentException("Argument 'Subject' is unsatisfactory", nameof(Subject));
        if (string.IsNullOrEmpty(Date) || !Helper.IsValidIso8601DateTime(Date)) 
            throw new ArgumentException("Argument 'Date' is unsatisfactory", nameof(Date));
        if (string.IsNullOrEmpty(Content) || Content.Length > 200)
            throw new ArgumentException("Argument 'Content' is unsatisfactory", nameof(Content));
    }
}