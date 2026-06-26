using System.Diagnostics.CodeAnalysis;
using CsvHelper.Configuration.Attributes;
using Uaf.Core.Helpers;

namespace Uaf.Core.Models;

public sealed record UafPayload
{
    [Name("subject")]
    public required string Subject { get; init; }
    [Name("date")]
    public required string Date { get; init; }
    [Name("date")]
    public required string Content { get; set; }
    [Name("tags")]
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

    [SetsRequiredMembers]
    public UafPayload(string subject, string date, string content, IReadOnlyList<string> tags) : this()
    {
        Subject = subject;
        Date = date;
        Content = content;
        Tags = tags;
    }
}