using System.Collections.ObjectModel;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace UnifiedAssignmentFormat;

public sealed partial class UafArtifactPackage
{
    private static readonly JsonSerializerOptions ManifestJsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly ReadOnlyDictionary<string, byte[]> _artifacts;

    private UafArtifactPackage(
        UafArtifactManifest manifest,
        UafPayload payload,
        IReadOnlyDictionary<string, byte[]> artifacts)
    {
        Manifest = manifest;
        Payload = payload;
        _artifacts = new ReadOnlyDictionary<string, byte[]>(
            artifacts.ToDictionary(
                pair => pair.Key,
                pair => pair.Value.ToArray(),
                StringComparer.Ordinal));
    }

    public UafArtifactManifest Manifest { get; }

    public UafPayload Payload { get; }

    public IReadOnlyDictionary<string, byte[]> Artifacts => _artifacts.ToDictionary(
        pair => pair.Key,
        pair => pair.Value.ToArray(),
        StringComparer.Ordinal);

    public string Csv => UafCsv.DecodeUtf8(GetArtifact(Manifest.Entrypoints.Payload));

    public string Html => UafCsv.DecodeUtf8(GetArtifact(Manifest.Entrypoints.Display));

    public byte[] PdfBytes => GetArtifact(Manifest.Entrypoints.Exchange);

    public static UafArtifactPackage Create(UafPayload payload, DateTimeOffset? createdAt = null)
    {
        ArgumentNullException.ThrowIfNull(payload);

        var artifacts = new Dictionary<string, byte[]>(StringComparer.Ordinal)
        {
            [UafConstants.PayloadFileName] = UafCsv.SerializeToUtf8(payload),
            [UafConstants.DisplayFileName] = Utf8NoBom(UafHtml.Render(payload)),
            [UafConstants.ExchangePdfFileName] = UafPdf.Create(payload)
        };

        var manifest = BuildManifest(artifacts, createdAt ?? DateTimeOffset.UtcNow);
        return new UafArtifactPackage(manifest, payload, artifacts);
    }

    public static UafArtifactPackage Read(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        if (Directory.Exists(path))
        {
            return ReadDirectory(path);
        }

        if (File.Exists(path))
        {
            return ReadZip(path);
        }

        throw new DirectoryNotFoundException($"UAF package path not found: {path}");
    }

    public static UafArtifactPackage ReadDirectory(string directoryPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directoryPath);

        var root = Path.GetFullPath(directoryPath);
        var manifestPath = Path.Combine(root, UafConstants.ManifestFileName);
        if (!File.Exists(manifestPath))
        {
            throw new UafException(UafErrorCode.InvalidPackage, "Package is missing uaf-manifest.json.");
        }

        var manifest = ReadManifest(File.ReadAllBytes(manifestPath));
        ValidateManifestShape(manifest);

        var artifacts = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var artifact in manifest.Artifacts)
        {
            var artifactPath = ResolvePackagePath(root, artifact.Path);
            if (!File.Exists(artifactPath))
            {
                throw new UafException(UafErrorCode.InvalidPackage, $"Package is missing artifact: {artifact.Path}");
            }

            var bytes = File.ReadAllBytes(artifactPath);
            AssertArtifactIntegrity(artifact, bytes);
            artifacts[artifact.Path] = bytes;
        }

        return FromVerifiedArtifacts(manifest, artifacts);
    }

    public static UafArtifactPackage ReadZip(string zipPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(zipPath);

        using var file = File.OpenRead(zipPath);
        using var archive = new ZipArchive(file, ZipArchiveMode.Read, leaveOpen: false);
        var manifestEntry = archive.GetEntry(UafConstants.ManifestFileName);
        if (manifestEntry is null)
        {
            throw new UafException(UafErrorCode.InvalidPackage, "ZIP package is missing uaf-manifest.json.");
        }

        var manifest = ReadManifest(ReadEntryBytes(manifestEntry));
        ValidateManifestShape(manifest);

        var artifacts = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var artifact in manifest.Artifacts)
        {
            EnsureSafeRelativePath(artifact.Path);
            var entry = archive.GetEntry(artifact.Path);
            if (entry is null)
            {
                throw new UafException(UafErrorCode.InvalidPackage, $"ZIP package is missing artifact: {artifact.Path}");
            }

            var bytes = ReadEntryBytes(entry);
            AssertArtifactIntegrity(artifact, bytes);
            artifacts[artifact.Path] = bytes;
        }

        return FromVerifiedArtifacts(manifest, artifacts);
    }

    public void WriteDirectory(string directoryPath, bool overwrite = false)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directoryPath);

        var root = Path.GetFullPath(directoryPath);
        if (Directory.Exists(root))
        {
            if (!overwrite && Directory.EnumerateFileSystemEntries(root).Any())
            {
                throw new IOException($"Directory already exists and is not empty: {root}");
            }

            if (overwrite)
            {
                Directory.Delete(root, recursive: true);
            }
        }

        Directory.CreateDirectory(root);
        foreach (var artifact in Manifest.Artifacts)
        {
            var path = ResolvePackagePath(root, artifact.Path);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllBytes(path, GetArtifact(artifact.Path));
        }

        File.WriteAllBytes(
            Path.Combine(root, UafConstants.ManifestFileName),
            Utf8NoBom(JsonSerializer.Serialize(Manifest, ManifestJsonOptions) + "\n"));
    }

    public void WriteZip(string zipPath, bool overwrite = false)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(zipPath);

        var fullPath = Path.GetFullPath(zipPath);
        if (File.Exists(fullPath))
        {
            if (!overwrite)
            {
                throw new IOException($"ZIP file already exists: {fullPath}");
            }

            File.Delete(fullPath);
        }

        var parent = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(parent))
        {
            Directory.CreateDirectory(parent);
        }

        using var file = File.Create(fullPath);
        using var archive = new ZipArchive(file, ZipArchiveMode.Create);

        WriteZipEntry(archive, UafConstants.ManifestFileName, Utf8NoBom(JsonSerializer.Serialize(Manifest, ManifestJsonOptions) + "\n"));
        foreach (var artifact in Manifest.Artifacts)
        {
            WriteZipEntry(archive, artifact.Path, GetArtifact(artifact.Path));
        }
    }

    public byte[] GetArtifact(string relativePath)
    {
        if (!_artifacts.TryGetValue(relativePath, out var bytes))
        {
            throw new KeyNotFoundException($"Artifact not loaded: {relativePath}");
        }

        return bytes.ToArray();
    }

    private static UafArtifactPackage FromVerifiedArtifacts(
        UafArtifactManifest manifest,
        IReadOnlyDictionary<string, byte[]> artifacts)
    {
        var csvPayload = UafCsv.Parse(RequiredArtifact(artifacts, manifest.Entrypoints.Payload));
        var htmlPayload = UafHtml.ExtractPayload(UafCsv.DecodeUtf8(RequiredArtifact(artifacts, manifest.Entrypoints.Display)));
        UafPayload.EnsureSame("HTML", csvPayload, htmlPayload);

        var pdfBytes = RequiredArtifact(artifacts, manifest.Entrypoints.Exchange);
        var pdfPayload = UafPdf.ExtractPayload(pdfBytes);
        UafPayload.EnsureSame("PDF", csvPayload, pdfPayload);

        return new UafArtifactPackage(manifest, csvPayload, artifacts);
    }

    private static UafArtifactManifest BuildManifest(
        IReadOnlyDictionary<string, byte[]> artifacts,
        DateTimeOffset createdAt)
    {
        var artifactEntries = new[]
        {
            CreateEntry("payload.csv", UafConstants.PayloadFileName, "text/csv; charset=utf-8", artifacts[UafConstants.PayloadFileName]),
            CreateEntry("display.html", UafConstants.DisplayFileName, "text/html; charset=utf-8", artifacts[UafConstants.DisplayFileName]),
            CreateEntry("exchange.pdf", UafConstants.ExchangePdfFileName, "application/pdf", artifacts[UafConstants.ExchangePdfFileName])
        };

        return new UafArtifactManifest
        {
            Schema = "../../spec/uaf-artifact-manifest.schema.json",
            CreatedAt = createdAt,
            Entrypoints = new UafPackageEntrypoints(),
            Artifacts = artifactEntries,
            Pipeline = new UafPipelineInfo
            {
                Renderer = "native-pdf",
                PrintEngine = "dotnet-native",
                PayloadAttachment = UafConstants.PayloadFileName
            }
        };
    }

    private static UafArtifactEntry CreateEntry(string role, string path, string mediaType, byte[] bytes)
    {
        return new UafArtifactEntry
        {
            Role = role,
            Path = path,
            MediaType = mediaType,
            Bytes = bytes.LongLength,
            Sha256 = Sha256(bytes)
        };
    }

    private static UafArtifactManifest ReadManifest(byte[] bytes)
    {
        try
        {
            return JsonSerializer.Deserialize<UafArtifactManifest>(bytes, ManifestJsonOptions)
                ?? throw new UafException(UafErrorCode.InvalidPackage, "Manifest JSON is empty.");
        }
        catch (JsonException ex)
        {
            throw new UafException(UafErrorCode.InvalidPackage, "Manifest JSON is invalid.", ex);
        }
    }

    private static void ValidateManifestShape(UafArtifactManifest manifest)
    {
        if (manifest.SchemaVersion != UafConstants.Version)
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Unsupported manifest schemaVersion: {manifest.SchemaVersion}");
        }

        if (manifest.PackageKind != "uaf-artifact-set")
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Unsupported packageKind: {manifest.PackageKind}");
        }

        if (manifest.UafVersion != UafConstants.Version)
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Unsupported uafVersion: {manifest.UafVersion}");
        }

        if (manifest.Pipeline.PayloadAttachment != UafConstants.PayloadFileName)
        {
            throw new UafException(UafErrorCode.InvalidPackage, "Manifest pipeline payloadAttachment must be uaf_payload.csv.");
        }

        if (manifest.Pipeline.Renderer is not ("html-to-pdf" or "native-pdf"))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Unsupported pipeline renderer: {manifest.Pipeline.Renderer}");
        }

        if (manifest.Pipeline.PrintEngine is not ("browser-print" or "pdf-lib" or "dotnet-native"))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Unsupported pipeline printEngine: {manifest.Pipeline.PrintEngine}");
        }

        EnsureSafeRelativePath(manifest.Entrypoints.Payload);
        EnsureSafeRelativePath(manifest.Entrypoints.Display);
        EnsureSafeRelativePath(manifest.Entrypoints.Exchange);

        if (manifest.Artifacts.Count < 3)
        {
            throw new UafException(UafErrorCode.InvalidPackage, "Manifest must list at least three artifacts.");
        }

        var paths = new HashSet<string>(StringComparer.Ordinal);
        var roles = new HashSet<string>(StringComparer.Ordinal);
        foreach (var artifact in manifest.Artifacts)
        {
            ValidateArtifact(artifact);
            if (!paths.Add(artifact.Path))
            {
                throw new UafException(UafErrorCode.InvalidPackage, $"Duplicate artifact path: {artifact.Path}");
            }

            if (!roles.Add(artifact.Role) && artifact.Role != "supporting")
            {
                throw new UafException(UafErrorCode.InvalidPackage, $"Duplicate required artifact role: {artifact.Role}");
            }
        }

        foreach (var requiredRole in new[] { "payload.csv", "display.html", "exchange.pdf" })
        {
            if (!roles.Contains(requiredRole))
            {
                throw new UafException(UafErrorCode.InvalidPackage, $"Manifest is missing required role: {requiredRole}");
            }
        }

        RequireArtifactContract(manifest, "payload.csv", UafConstants.PayloadFileName, "text/csv; charset=utf-8");
        RequireArtifactContract(manifest, "display.html", UafConstants.DisplayFileName, "text/html; charset=utf-8");
        RequireArtifactContract(manifest, "exchange.pdf", UafConstants.ExchangePdfFileName, "application/pdf");

        foreach (var entrypoint in new[] { manifest.Entrypoints.Payload, manifest.Entrypoints.Display, manifest.Entrypoints.Exchange })
        {
            if (!paths.Contains(entrypoint))
            {
                throw new UafException(UafErrorCode.InvalidPackage, $"Manifest entrypoint is not listed as an artifact: {entrypoint}");
            }
        }
    }

    private static void RequireArtifactContract(
        UafArtifactManifest manifest,
        string role,
        string requiredPath,
        string requiredMediaType)
    {
        var artifact = manifest.Artifacts.Single(entry => entry.Role == role);
        if (artifact.Path != requiredPath)
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Artifact role {role} must use path {requiredPath}.");
        }

        if (!StringComparer.OrdinalIgnoreCase.Equals(artifact.MediaType, requiredMediaType))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Artifact {requiredPath} must use mediaType {requiredMediaType}.");
        }
    }

    private static void ValidateArtifact(UafArtifactEntry artifact)
    {
        if (artifact.Role is not ("payload.csv" or "display.html" or "exchange.pdf" or "supporting"))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Unsupported artifact role: {artifact.Role}");
        }

        EnsureSafeRelativePath(artifact.Path);
        if (string.IsNullOrWhiteSpace(artifact.MediaType))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Artifact {artifact.Path} must declare mediaType.");
        }

        if (artifact.Bytes < 0)
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Artifact {artifact.Path} has invalid byte length.");
        }

        if (!Sha256Regex().IsMatch(artifact.Sha256))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Artifact {artifact.Path} has invalid sha256.");
        }
    }

    private static void AssertArtifactIntegrity(UafArtifactEntry artifact, byte[] bytes)
    {
        if (artifact.Bytes != bytes.LongLength)
        {
            throw new UafException(
                UafErrorCode.HashMismatch,
                $"Artifact {artifact.Path} byte size mismatch: expected {artifact.Bytes}, got {bytes.LongLength}.");
        }

        var actualHash = Sha256(bytes);
        if (!StringComparer.Ordinal.Equals(artifact.Sha256, actualHash))
        {
            throw new UafException(UafErrorCode.HashMismatch, $"Artifact {artifact.Path} sha256 mismatch.");
        }
    }

    private static byte[] RequiredArtifact(IReadOnlyDictionary<string, byte[]> artifacts, string path)
    {
        if (!artifacts.TryGetValue(path, out var bytes))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Required artifact is not loaded: {path}");
        }

        return bytes;
    }

    private static string ResolvePackagePath(string root, string relativePath)
    {
        EnsureSafeRelativePath(relativePath);

        var normalizedRoot = Path.GetFullPath(root);
        var resolvedPath = Path.GetFullPath(Path.Combine(normalizedRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        var rootWithSeparator = normalizedRoot.EndsWith(Path.DirectorySeparatorChar)
            ? normalizedRoot
            : normalizedRoot + Path.DirectorySeparatorChar;

        if (!resolvedPath.Equals(normalizedRoot, StringComparison.OrdinalIgnoreCase)
            && !resolvedPath.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
        {
            throw new UafException(
                UafErrorCode.InvalidPackage,
                $"Package path escapes the package root: {relativePath}");
        }

        return resolvedPath;
    }

    private static void EnsureSafeRelativePath(string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath)
            || Path.IsPathRooted(relativePath)
            || relativePath.Contains('\\', StringComparison.Ordinal)
            || relativePath.Contains("://", StringComparison.Ordinal)
            || DrivePrefixRegex().IsMatch(relativePath)
            || relativePath.Split('/').Any(segment => segment is "" or "." or ".."))
        {
            throw new UafException(UafErrorCode.InvalidPackage, $"Invalid package path: {relativePath}");
        }
    }

    private static byte[] ReadEntryBytes(ZipArchiveEntry entry)
    {
        using var stream = entry.Open();
        using var output = new MemoryStream();
        stream.CopyTo(output);
        return output.ToArray();
    }

    private static void WriteZipEntry(ZipArchive archive, string path, byte[] bytes)
    {
        EnsureSafeRelativePath(path);
        var entry = archive.CreateEntry(path, CompressionLevel.Optimal);
        using var stream = entry.Open();
        stream.Write(bytes);
    }

    private static byte[] Utf8NoBom(string text)
    {
        return new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(text);
    }

    private static string Sha256(byte[] bytes)
    {
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    [GeneratedRegex("^[a-f0-9]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Regex();

    [GeneratedRegex("^[A-Za-z]:", RegexOptions.CultureInvariant)]
    private static partial Regex DrivePrefixRegex();
}
