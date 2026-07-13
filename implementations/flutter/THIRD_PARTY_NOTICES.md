# Third-party notices

## Noto Sans SC

The zlib-compressed source font data bundled in `lib/src/font_data.dart` is
generated from `Noto Sans SC 400 Chinese Simplified` distributed by
`@fontsource/noto-sans-sc` version 5.2.9.

During PDF generation, the SDK derives and embeds a new TrueType subset that
contains only the glyphs required by that UAF document (plus required fallback
characters). The generated PDF also contains a `ToUnicode` map so its text
remains selectable and extractable. Both the bundled source font data and the
derived subsets are covered by the license below.

- Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name
  `Source`.
- Copyright 2015-2021 Google LLC.
- Licensed under the SIL Open Font License, Version 1.1.

The SIL Open Font License 1.1 text distributed with the SDK is included in
`NotoSansSC-LICENSE.txt`.
