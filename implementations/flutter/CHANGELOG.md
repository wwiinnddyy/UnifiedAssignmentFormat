# Changelog

## 1.0.0

- Implement the immutable UAF v1.0 assignment model and validation errors.
- Add RFC 4180 CSV, self-contained HTML, and multi-page PDF round-trips.
- Add UAF PDF payload extraction and validation across reference implementations.
- Bundle Noto Sans SC 400 source data and embed a per-document TrueType subset
  with a `ToUnicode` map for selectable Chinese PDF text.
- Constrain `pdf` to the verified `>=3.11.3 <3.13.0` range because subset
  generation relies on its exported `TtfParser` and internal `TtfWriter` API.
- Add verified `.uaf` directory and `.uaf.zip` artifact packages.
- Add `UafPackageReadLimits`, ZIP envelope/header/CRC-32 checks, compression
  ratio limits, and atomic directory/ZIP replacement.
- Add `fromBytesAsync` and `readAsync` worker-isolate verification APIs for
  Dart VM and Flutter mobile/desktop clients.
- Add platform-neutral `UafArtifactManifest.parseValidated` / `validate`
  APIs so Flutter Web can enforce the complete manifest contract.
- Reject forged ZIP size declarations with bounded streaming decompression
  before allocating the full entry output.
- Enforce visible HTML/payload agreement, inert markup, and lossless two-row
  tag continuation cards.
- Require the exact PDF name-tree and FileSpec `/UF` identity, and reject
  characters unavailable in the bundled PDF font instead of replacing them.
- Support Flutter mobile, desktop, and web through platform-specific entry points.
- Include the Noto Sans SC third-party notice and SIL Open Font License 1.1.
