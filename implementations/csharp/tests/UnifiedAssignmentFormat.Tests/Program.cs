using UnifiedAssignmentFormat;

var tests = new (string Name, Action Run)[]
{
    ("CSV round-trips multiple assignments", CsvRoundTrip),
    ("HTML round-trips multiple assignments", HtmlRoundTrip),
    ("PDF embeds and restores multiple assignments", PdfRoundTrip),
    ("Artifact package preserves the document", PackageRoundTrip),
    ("Empty documents are rejected", EmptyDocumentRejected),
};

foreach (var (name, run) in tests)
{
    run();
    Console.WriteLine($"PASS {name}");
}

static UafDocument SampleDocument() => new([
    new UafAssignment("数学", "2026-05-19", "完成第1、2题", ["必做"]),
    new UafAssignment("语文", "2026-05-19", "背诵古诗\n完成仿写", ["背诵"]),
    new UafAssignment("英语", "2026-05-19", "Read Unit 3", []),
]);

static void CsvRoundTrip()
{
    var expected = SampleDocument();
    AssertEqual(expected, UafCsv.Parse(UafCsv.Serialize(expected)));
}

static void HtmlRoundTrip()
{
    var expected = SampleDocument();
    var html = UafHtml.Render(expected);
    if (Count(html, "<article class=\"card\">") < expected.Count) throw new Exception("HTML did not render all cards.");
    AssertEqual(expected, UafHtml.ExtractPayload(html));
}

static void PdfRoundTrip()
{
    var expected = SampleDocument();
    var pdf = UafPdf.Create(expected);
    if (!pdf.AsSpan(0, 4).SequenceEqual("%PDF"u8)) throw new Exception("Invalid PDF header.");
    AssertEqual(expected, UafPdf.ExtractPayload(pdf));
}

static void PackageRoundTrip()
{
    var expected = SampleDocument();
    var package = UafArtifactPackage.Create(expected, DateTimeOffset.Parse("2026-06-08T00:00:00Z"));
    AssertEqual(expected, package.Payload);
}

static void EmptyDocumentRejected()
{
    try { _ = new UafDocument([]); }
    catch (UafException) { return; }
    throw new Exception("Expected an empty document to be rejected.");
}

static void AssertEqual(UafDocument expected, UafDocument actual)
{
    if (!expected.Equals(actual)) throw new Exception("Documents differ.");
}

static int Count(string text, string value)
{
    var count = 0; var index = 0;
    while ((index = text.IndexOf(value, index, StringComparison.Ordinal)) >= 0) { count++; index += value.Length; }
    return count;
}
