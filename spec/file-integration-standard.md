# UAF File Integration Standard v1.0

This document defines how a program should package, discover, read, and verify a complete UAF artifact set.

The canonical exchange file remains the multi-assignment UAF PDF described in [`uaf-v1.0.md`](./uaf-v1.0.md). An artifact set is the engineering package used by builders, validators, archives, and integration tests when the payload CSV, display HTML, and exchange PDF must travel together.

## 1. Package Shape

A UAF artifact set MAY be stored as either:

- a directory whose name ends with `.uaf`
- a ZIP archive whose name ends with `.uaf.zip`

Both forms MUST contain the same relative file layout:

```text
uaf-manifest.json
uaf_payload.csv
display.html
document.pdf
```

Extra files are allowed only when they are listed in `uaf-manifest.json`.

## 2. Manifest

The package entry point is always `uaf-manifest.json`. Programs MUST read this file first.

The manifest MUST conform to [`uaf-artifact-manifest.schema.json`](./uaf-artifact-manifest.schema.json). It records:

- `schemaVersion`: manifest schema version, currently `1.0`
- `packageKind`: fixed value `uaf-artifact-set`
- `uafVersion`: UAF data and rendering standard version, currently `1.0`
- `createdAt`: ISO 8601 creation time
- `entrypoints`: relative paths for the payload CSV, display HTML, and exchange PDF
- `artifacts`: every packaged file with role, path, media type, byte size, and SHA-256 hash
- `pipeline`: how the display and PDF artifacts were produced

Required artifact roles:

| Role | Required path | Media type | Purpose |
|------|---------------|------------|---------|
| `payload.csv` | `uaf_payload.csv` | `text/csv; charset=utf-8` | Machine-readable payload source |
| `display.html` | `display.html` | `text/html; charset=utf-8` | Self-contained printable display artifact |
| `exchange.pdf` | `document.pdf` | `application/pdf` | Official cross-platform exchange file |

Optional supporting files MUST use role `supporting`.

The path in each artifact MUST be relative, use `/` as the separator in JSON, and MUST NOT contain `..`, an absolute path, a drive prefix, or a URL.

## 3. Reading Algorithm

A program that reads a UAF artifact set MUST:

1. Open the directory or unzip archive into a package root.
2. Read and parse `uaf-manifest.json` as UTF-8 JSON.
3. Verify `packageKind === "uaf-artifact-set"` and supported `schemaVersion` / `uafVersion`.
4. Resolve every artifact path under the package root and reject path traversal.
5. Read every listed artifact and compare its byte length and SHA-256 hash with the manifest.
6. Parse `entrypoints.payload` using the CSV schema.
7. Validate `entrypoints.display` with the UAF HTML validator.
8. Validate `entrypoints.exchange` with the UAF PDF validator.
9. Compare the payload recovered from CSV, HTML, and PDF. All three MUST be identical.

If any step fails, the package MUST be treated as invalid. Consumers MAY still show the PDF visually, but MUST NOT import the payload into a system of record.

## 4. Packaging Algorithm

A builder that creates a UAF artifact set SHOULD:

1. Validate or create a non-empty `UafDocument`.
2. Serialize every assignment row, in order, as `uaf_payload.csv`.
3. Render `display.html` as a self-contained UAF HTML document.
4. Print `display.html` to a one-or-more-page PDF and embed the same `uaf_payload.csv` as `document.pdf`.
5. Write the CSV, HTML, and PDF into a clean `.uaf` directory.
6. Compute each file's byte size and SHA-256 hash.
7. Write `uaf-manifest.json` last, after all file hashes are known.
8. Optionally ZIP the directory without changing relative paths.

The manifest SHOULD name the production path explicitly:

```json
{
  "pipeline": {
      "renderer": "html-to-pdf",
      "printEngine": "browser-print",
      "payloadAttachment": "uaf_payload.csv"
  }
}
```

Native renderers MAY use another declared engine when the manifest schema allows it, such as `dotnet-native` for the C# reference implementation or `dart-native` for the Flutter / Dart reference implementation.

## 5. TypeScript Demonstration

The TypeScript reference implementation includes two runnable scripts:

```bash
cd implementations/typescript
pnpm build
pnpm run generate:sample
pnpm run package:sample
pnpm run read:sample-package
```

- `package:sample` creates `examples/sample-homework.uaf/`.
- `read:sample-package` reads the manifest, verifies hashes, validates CSV/HTML/PDF, and confirms that all payloads match.
