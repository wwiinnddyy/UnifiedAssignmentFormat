using CsvHelper.Configuration.Attributes;

namespace Uaf.Core.Models;

internal class UafPayloadReadyToConvert
{
    [Name("subject")]
    public string Subject { get; set; }
    [Name("date")]
    public string Date { get; set; }
    [Name("content")]
    public string Content { get; set; }
    [Name("tags")]
    public string Tags { get; set; }

    public static UafPayload ConvertToFinal(UafPayloadReadyToConvert rtc)
    {
        return new UafPayload(rtc.Subject, rtc.Date, rtc.Content, rtc.Tags.Split(';', StringSplitOptions.RemoveEmptyEntries).AsReadOnly());
    }

    public static UafPayloadReadyToConvert ConvertToRtc(UafPayload payload)
    {
        return new UafPayloadReadyToConvert()
        {
            Subject = payload.Subject,
            Date = payload.Date,
            Content = payload.Content,
            Tags = string.Join(";", payload.Tags),
        };
    }
}