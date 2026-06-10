using System.Text.Json.Serialization;

namespace UnifiedAssignmentFormat;

public sealed record UafArtifactManifest
{
    [JsonPropertyName("$schema")]
    public string? Schema { get; init; }

    [JsonPropertyName("schemaVersion")]
    public string SchemaVersion { get; init; } = UafConstants.Version;

    [JsonPropertyName("packageKind")]
    public string PackageKind { get; init; } = "uaf-artifact-set";

    [JsonPropertyName("uafVersion")]
    public string UafVersion { get; init; } = UafConstants.Version;

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; init; }

    [JsonPropertyName("entrypoints")]
    public UafPackageEntrypoints Entrypoints { get; init; } = new();

    [JsonPropertyName("artifacts")]
    public IReadOnlyList<UafArtifactEntry> Artifacts { get; init; } = Array.Empty<UafArtifactEntry>();

    [JsonPropertyName("pipeline")]
    public UafPipelineInfo Pipeline { get; init; } = new();
}

public sealed record UafPackageEntrypoints
{
    [JsonPropertyName("payload")]
    public string Payload { get; init; } = UafConstants.PayloadFileName;

    [JsonPropertyName("display")]
    public string Display { get; init; } = UafConstants.DisplayFileName;

    [JsonPropertyName("exchange")]
    public string Exchange { get; init; } = UafConstants.ExchangePdfFileName;
}

public sealed record UafArtifactEntry
{
    [JsonPropertyName("role")]
    public string Role { get; init; } = string.Empty;

    [JsonPropertyName("path")]
    public string Path { get; init; } = string.Empty;

    [JsonPropertyName("mediaType")]
    public string MediaType { get; init; } = string.Empty;

    [JsonPropertyName("bytes")]
    public long Bytes { get; init; }

    [JsonPropertyName("sha256")]
    public string Sha256 { get; init; } = string.Empty;
}

public sealed record UafPipelineInfo
{
    [JsonPropertyName("renderer")]
    public string Renderer { get; init; } = "native-pdf";

    [JsonPropertyName("printEngine")]
    public string PrintEngine { get; init; } = "dotnet-native";

    [JsonPropertyName("payloadAttachment")]
    public string PayloadAttachment { get; init; } = UafConstants.PayloadFileName;
}
