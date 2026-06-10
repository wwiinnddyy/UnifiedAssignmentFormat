using UnifiedAssignmentFormat;

var tests = new (string Name, Action Test)[]
{
    ("CSV round-trips multilingual payloads", CsvRoundTripsMultilingualPayloads),
    ("CSV handles multiline and escaped fields", CsvHandlesMultilineAndEscapedFields),
    ("CSV rejects invalid data", CsvRejectsInvalidData),
    ("HTML embeds and reads canonical CSV", HtmlEmbedsAndReadsCanonicalCsv),
    ("PDF embeds and reads payload CSV", PdfEmbedsAndReadsPayloadCsv),
    ("Package writes and reads directory and zip", PackageWritesAndReadsDirectoryAndZip),
    ("Package reads repository sample package", PackageReadsRepositorySamplePackage),
    ("Package rejects tampered artifacts", PackageRejectsTamperedArtifacts)
};

var passed = 0;
foreach (var (name, test) in tests)
{
    try
    {
        test();
        Console.WriteLine($"PASS {name}");
        passed++;
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"FAIL {name}");
        Console.Error.WriteLine(ex);
        Environment.ExitCode = 1;
        return;
    }
}

Console.WriteLine($"All {passed} tests passed.");

static void CsvRoundTripsMultilingualPayloads()
{
    var payload = SamplePayload();
    var csv = UafCsv.Serialize(payload);

    AssertEqual("subject,date,content,tags\n", csv[.."subject,date,content,tags\n".Length]);
    AssertPayload(payload, UafCsv.Parse(csv));
}

static void CsvHandlesMultilineAndEscapedFields()
{
    var payload = new UafPayload(
        "语文",
        "2026-05-19",
        "背诵《静夜思》\n第二段抄写生字，标注“意象”。",
        ["必做", "古诗"]);

    var csv = UafCsv.Serialize(payload);
    AssertTrue(csv.Contains("\"背诵", StringComparison.Ordinal), "multiline content should be quoted");
    AssertTrue(csv.Contains("“意象”", StringComparison.Ordinal), "unicode punctuation should be preserved");
    AssertPayload(payload, UafCsv.Parse(csv));
}

static void CsvRejectsInvalidData()
{
    AssertThrows<UafException>(
        () => UafCsv.Parse("subject,date,content,tags\n数学,not-a-date,作业,\n"),
        ex => ex.Code == UafErrorCode.InvalidPayload);

    AssertThrows<UafException>(
        () => new UafPayload("数学", "2026-05-19", "作业", ["a;b"]),
        ex => ex.Code == UafErrorCode.InvalidPayload);

    AssertThrows<UafException>(
        () => UafCsv.Parse("subject,date,content,tags\n数学,2026-05-19,作业,\n英语,2026-05-20,作业,\n"),
        ex => ex.Code == UafErrorCode.InvalidCsv);
}

static void HtmlEmbedsAndReadsCanonicalCsv()
{
    var payload = SamplePayload();
    var html = UafHtml.Render(payload);

    AssertTrue(html.Contains("class=\"card\"", StringComparison.Ordinal), "HTML should render the visual card");
    AssertTrue(html.Contains("使用 UAF v1.0 导出", StringComparison.Ordinal), "HTML should render the watermark");
    AssertPayload(payload, UafHtml.ExtractPayload(html));
}

static void PdfEmbedsAndReadsPayloadCsv()
{
    var payload = SamplePayload();
    var pdf = UafPdf.Create(payload);

    AssertTrue(pdf.Length > 1000, "PDF should contain a visible page and attachment objects");
    AssertPayload(payload, UafPdf.ExtractPayload(pdf));
}

static void PackageWritesAndReadsDirectoryAndZip()
{
    var payload = SamplePayload();
    var package = UafArtifactPackage.Create(payload, DateTimeOffset.Parse("2026-06-08T00:00:00Z"));
    using var temp = new TempWorkspace();

    var directoryPath = Path.Combine(temp.Path, "homework.uaf");
    package.WriteDirectory(directoryPath);
    var readDirectory = UafArtifactPackage.Read(directoryPath);
    AssertPayload(payload, readDirectory.Payload);
    AssertTrue(File.Exists(Path.Combine(directoryPath, "display.html")), "display.html should be exported");

    var zipPath = Path.Combine(temp.Path, "homework.uaf.zip");
    package.WriteZip(zipPath);
    var readZip = UafArtifactPackage.Read(zipPath);
    AssertPayload(payload, readZip.Payload);
}

static void PackageReadsRepositorySamplePackage()
{
    var repoRoot = FindRepoRoot();
    var samplePackage = Path.Combine(repoRoot, "examples", "sample-homework.uaf");
    var package = UafArtifactPackage.Read(samplePackage);

    AssertEqual("数学", package.Payload.Subject);
    AssertEqual("2026-05-19", package.Payload.Date);
    AssertEqual(3, package.Payload.Tags.Count);
}

static void PackageRejectsTamperedArtifacts()
{
    var package = UafArtifactPackage.Create(SamplePayload());
    using var temp = new TempWorkspace();
    var directoryPath = Path.Combine(temp.Path, "tampered.uaf");
    package.WriteDirectory(directoryPath);
    File.AppendAllText(Path.Combine(directoryPath, "uaf_payload.csv"), "# tampered");

    AssertThrows<UafException>(
        () => UafArtifactPackage.Read(directoryPath),
        ex => ex.Code == UafErrorCode.HashMismatch);
}

static UafPayload SamplePayload()
{
    return new UafPayload(
        "数学",
        "2026-05-19",
        "完成课本第45页第1、2题，请拍照上传。",
        ["必做", "几何", "重难点"]);
}

static string FindRepoRoot()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "spec", "uaf-v1.0.md")))
        {
            return directory.FullName;
        }

        directory = directory.Parent;
    }

    throw new InvalidOperationException("Could not locate repository root.");
}

static void AssertPayload(UafPayload expected, UafPayload actual)
{
    if (!expected.Equals(actual))
    {
        throw new InvalidOperationException($"Payload mismatch. Expected {expected}; got {actual}.");
    }
}

static void AssertEqual<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}; got {actual}.");
    }
}

static void AssertTrue(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

static void AssertThrows<TException>(Action action, Func<TException, bool> predicate)
    where TException : Exception
{
    try
    {
        action();
    }
    catch (TException ex) when (predicate(ex))
    {
        return;
    }

    throw new InvalidOperationException($"Expected {typeof(TException).Name}.");
}

internal sealed class TempWorkspace : IDisposable
{
    public TempWorkspace()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "uaf-csharp-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
