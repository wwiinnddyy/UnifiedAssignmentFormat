namespace UnifiedAssignmentFormat;

public static class UafConstants
{
    public const string Version = "1.0";
    public const string PayloadFileName = "uaf_payload.csv";
    public const string ManifestFileName = "uaf-manifest.json";
    public const string DisplayFileName = "display.html";
    public const string ExchangePdfFileName = "document.pdf";
    public const string CsvHeader = "subject,date,content,tags";
    public const string WatermarkText = "本文件符合UAF标准规范";

    public const int SubjectMaxLength = 200;
    public const int ContentMaxLength = 2000;
    public const int TagMaxLength = 50;
    public const int TagMaxCount = 20;
}
