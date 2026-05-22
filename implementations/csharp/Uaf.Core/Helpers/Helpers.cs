using System.Globalization;

namespace Uaf.Core.Helpers;

public class Helper
{
    public static bool IsValidIso8601DateTime(string date)
    {
        string[] formats =
        [
            "yyyy-MM-dd",
            "yyyy-MM-ddTHH:mm:ss"
        ];

        return DateTime.TryParseExact(
            date,
            formats,
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out _
        );
    }
}