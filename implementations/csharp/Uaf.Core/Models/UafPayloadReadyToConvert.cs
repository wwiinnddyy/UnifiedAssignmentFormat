namespace Uaf.Core.Models;

internal class UafPayloadReadyToConvert
{
    public string Subject { get; set; }
    public string Date { get; set; }
    public string Content { get; set; }
    public string Tags { get; set; }

    public static UafPayload ConvertToFinal(UafPayloadReadyToConvert rtc)
    {
        return new UafPayload()
        {
            Subject = rtc.Subject,
            Date = rtc.Date,
            Content = rtc.Content,
            Tags = rtc.Tags.Split(';').AsReadOnly(),
        };
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