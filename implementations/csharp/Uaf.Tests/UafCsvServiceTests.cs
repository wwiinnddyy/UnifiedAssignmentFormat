using Uaf.Core.Models;
using Uaf.Core.Services;

namespace Uaf.Tests;

public class UafCsvServiceTests
{
    [Fact]
    public async Task Parse_EmptyString_ReturnsEmptyList()
    {
        var result = await UafCsvService.Parse("");
        Assert.Empty(result);
    }

    [Fact]
    public async Task Parse_WhitespaceString_ReturnsEmptyList()
    {
        var result = await UafCsvService.Parse("   ");
        Assert.Empty(result);
    }

    [Fact]
    public async Task Parse_NullString_ReturnsEmptyList()
    {
        var result = await UafCsvService.Parse(null!);
        Assert.Empty(result);
    }

    [Fact]
    public async Task Parse_SingleRecord_ReturnsPopulatedList()
    {
        var csv = "subject,date,content,tags\r\nTest Subject,2024-01-15,Test Content,tag1";
        var result = await UafCsvService.Parse(csv);

        var record = Assert.Single(result);
        Assert.Equal("Test Subject", record.Subject);
        Assert.Equal("2024-01-15", record.Date);
        Assert.Equal("Test Content", record.Content);
    }

    [Fact]
    public async Task Parse_MultipleRecords_ReturnsAllRecords()
    {
        var csv = "subject,date,content,tags\r\nSubject1,2024-01-15,Content1,tag1\r\nSubject2,2024-06-20,Content2,tag2";
        var result = await UafCsvService.Parse(csv);

        Assert.Equal(2, result.Count);
        Assert.Equal("Subject1", result[0].Subject);
        Assert.Equal("Subject2", result[1].Subject);
    }

    [Fact]
    public async Task Parse_Tags_SplitBySemicolon()
    {
        var csv = "subject,date,content,tags\r\nTest,2024-01-15,Content,tag1;tag2;tag3";
        var result = await UafCsvService.Parse(csv);

        var record = Assert.Single(result);
        Assert.Equal(3, record.Tags.Count);
        Assert.Equal(["tag1", "tag2", "tag3"], record.Tags);
    }

    [Fact]
    public async Task Parse_NoTags_ReturnsEmptyTagsList()
    {
        var csv = "subject,date,content,tags\r\nTest,2024-01-15,Content,";
        var result = await UafCsvService.Parse(csv);

        var record = Assert.Single(result);
        Assert.NotNull(record.Tags);
        Assert.Empty(record.Tags);
    }

    [Fact]
    public async Task Parse_DateTimeWithTimeComponent_Accepted()
    {
        var csv = "subject,date,content,tags\r\nTest,2024-01-15T14:30:00,Content,tag1";
        var result = await UafCsvService.Parse(csv);

        var record = Assert.Single(result);
        Assert.Equal("2024-01-15T14:30:00", record.Date);
    }

    [Fact]
    public async Task Parse_InvalidDate_ThrowsArgumentException()
    {
        var csv = "subject,date,content,tags\r\nTest,invalid-date,Content,tag1";
        await Assert.ThrowsAsync<ArgumentException>(() => UafCsvService.Parse(csv));
    }

    [Fact]
    public async Task Parse_EmptySubject_ThrowsArgumentException()
    {
        var csv = "subject,date,content,tags\r\n,2024-01-15,Content,tag1";
        await Assert.ThrowsAsync<ArgumentException>(() => UafCsvService.Parse(csv));
    }

    [Fact]
    public async Task Parse_SubjectTooLong_ThrowsArgumentException()
    {
        var longSubject = new string('x', 201);
        var csv = $"subject,date,content,tags\r\n{longSubject},2024-01-15,Content,tag1";
        await Assert.ThrowsAsync<ArgumentException>(() => UafCsvService.Parse(csv));
    }

    [Fact]
    public async Task Parse_ContentTooLong_ThrowsArgumentException()
    {
        var longContent = new string('x', 201);
        var csv = $"subject,date,content,tags\r\nTest,2024-01-15,{longContent},tag1";
        await Assert.ThrowsAsync<ArgumentException>(() => UafCsvService.Parse(csv));
    }

    [Fact]
    public async Task Parse_SubjectAtMaxLength_Accepted()
    {
        var subject = new string('x', 200);
        var csv = $"subject,date,content,tags\r\n{subject},2024-01-15,Content,tag1";
        var result = await UafCsvService.Parse(csv);
        Assert.Equal(subject, result[0].Subject);
    }

    [Fact]
    public async Task Parse_ContentAtMaxLength_Accepted()
    {
        var content = new string('x', 200);
        var csv = $"subject,date,content,tags\r\nTest,2024-01-15,{content},tag1";
        var result = await UafCsvService.Parse(csv);
        Assert.Equal(content, result[0].Content);
    }

    [Fact]
    public async Task Serialize_EmptyList_ReturnsHeaderOnly()
    {
        var result = await UafCsvService.Serialize([]);
        var lines = result.Split(["\r\n"], StringSplitOptions.None);

        Assert.Equal(2, lines.Length);
        Assert.Equal("subject,date,content,tags", lines[0]);
        Assert.Equal("", lines[1]);
    }

    [Fact]
    public async Task Serialize_SingleRecord_ReturnsCsvWithCorrectColumns()
    {
        var payloads = new List<UafPayload>
        {
            new("Test Subject", "2024-01-15", "Test Content", ["tag1"])
        };
        var result = await UafCsvService.Serialize(payloads);
        var lines = result.Split(["\r\n"], StringSplitOptions.RemoveEmptyEntries);

        Assert.Equal(2, lines.Length);
        Assert.Equal("subject,date,content,tags", lines[0]);
        Assert.Equal("Test Subject,2024-01-15,Test Content,tag1", lines[1]);
    }

    [Fact]
    public async Task Serialize_MultipleRecords_ReturnsAllRows()
    {
        var payloads = new List<UafPayload>
        {
            new("Subject1", "2024-01-15", "Content1", []),
            new("Subject2", "2024-06-20", "Content2", []),
        };
        var result = await UafCsvService.Serialize(payloads);
        var lines = result.Split(["\r\n"], StringSplitOptions.RemoveEmptyEntries);

        Assert.Equal(3, lines.Length);
        Assert.Equal("subject,date,content,tags", lines[0]);
        Assert.Equal("Subject1,2024-01-15,Content1,", lines[1]);
        Assert.Equal("Subject2,2024-06-20,Content2,", lines[2]);
    }

    [Fact]
    public async Task Serialize_Tags_JoinedBySemicolon()
    {
        var payloads = new List<UafPayload>
        {
            new("Test", "2024-01-15", "Content", ["tag1", "tag2", "tag3"])
        };
        var result = await UafCsvService.Serialize(payloads);

        Assert.Contains("tag1;tag2;tag3", result);
    }

    [Fact]
    public async Task Serialize_NoTags_EmptyTagsField()
    {
        var payloads = new List<UafPayload>
        {
            new("Test", "2024-01-15", "Content", [])
        };
        var result = await UafCsvService.Serialize(payloads);
        var lines = result.Split(["\r\n"], StringSplitOptions.RemoveEmptyEntries);

        Assert.Equal("Test,2024-01-15,Content,", lines[1]);
    }

    [Fact]
    public async Task Serialize_UsesWindowsLineEndings()
    {
        var payloads = new List<UafPayload>
        {
            new("Test", "2024-01-15", "Content", [])
        };
        var result = await UafCsvService.Serialize(payloads);

        Assert.Contains("\r\n", result);
    }

    [Fact]
    public async Task SerializeThenParse_RoundTripsCorrectly()
    {
        var original = new List<UafPayload>
        {
            new("Subject1", "2024-01-15", "Content1", ["tag1", "tag2"]),
            new("Subject2", "2024-06-20T10:30:00", "Content2", []),
            new("Subject3", "2024-12-31", "Content3", ["urgent", "review"]),
        };

        var csv = await UafCsvService.Serialize(original);
        var parsed = await UafCsvService.Parse(csv);

        Assert.Equal(original.Count, parsed.Count);
        for (int i = 0; i < original.Count; i++)
        {
            Assert.Equal(original[i].Subject, parsed[i].Subject);
            Assert.Equal(original[i].Date, parsed[i].Date);
            Assert.Equal(original[i].Content, parsed[i].Content);
            Assert.Equal(original[i].Tags, parsed[i].Tags);
        }
    }
}
