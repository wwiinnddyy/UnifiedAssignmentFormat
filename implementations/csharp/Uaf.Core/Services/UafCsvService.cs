using System.Globalization;
using CsvHelper;
using CsvHelper.Configuration;
using Uaf.Core.Models;

namespace Uaf.Core.Services;

public static class UafCsvService
{
    public static async Task<List<UafPayload>> Parse(string csv)
    {
        if (string.IsNullOrWhiteSpace(csv)) return [];
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            Mode = CsvMode.RFC4180,
            Delimiter = ",",
            AllowComments = false,
            HasHeaderRecord = true,
        };
        using var csvReader = new CsvReader(new StringReader(csv), config);
        var rtcResult = await csvReader.GetRecordsAsync<UafPayloadReadyToConvert>().ToListAsync();
        List<UafPayload> result = [];
        foreach (var rtc in rtcResult)
        {
            result.Add(UafPayloadReadyToConvert.ConvertToFinal(rtc));
        }
        return result;
    }

    public static async Task<string> Serialize(List<UafPayload> payloads)
    {
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            Mode = CsvMode.RFC4180,
            NewLine = "\r\n",
        };
        List<UafPayloadReadyToConvert> rtcs = [];
        foreach (var payload in payloads)
        {
            rtcs.Add(UafPayloadReadyToConvert.ConvertToRtc(payload));
        }
        await using var stringWriter = new StringWriter();
        await using var csvWriter = new CsvWriter(stringWriter, config);
        csvWriter.WriteHeader<UafPayloadReadyToConvert>();
        await csvWriter.NextRecordAsync();
        await csvWriter.WriteRecordsAsync(rtcs);
        return stringWriter.ToString();
    }
}