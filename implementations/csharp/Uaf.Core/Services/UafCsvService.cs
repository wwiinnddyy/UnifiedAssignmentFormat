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
        var result = await csvReader.GetRecordsAsync<UafPayload>().ToListAsync();
        return result;
    }

    public static async Task<string> Serialize(List<UafPayload> payload)
    {
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            Mode = CsvMode.RFC4180,
            NewLine = "\r\n",
        };
        await using var stringWriter = new StringWriter();
        await using var csvWriter = new CsvWriter(stringWriter, config);
        csvWriter.WriteHeader<UafPayload>();
        await csvWriter.NextRecordAsync();
        await csvWriter.WriteRecordsAsync(payload);
        return stringWriter.ToString();
    }
}