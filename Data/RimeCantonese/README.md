# Rime Cantonese Jyutping character data

This directory contains the one third-party Cantonese dataset explicitly
approved for Jiukong's Cantonese input mode.

- Upstream: `rime/rime-cantonese`
- Files: `jyut6ping3.chars.dict.yaml` and `jyut6ping3.words.dict.yaml`
- Pinned commit: `259f0e48bba840c3a2e0d117539e96937f3d89bc`
- Upstream data version: `2026.08.10`
- Character blob SHA: `f31eb5e66b0f26b6427306c514aa42d396c13a97`
- Word blob SHA: `5e581cee9fd38e6063e0ea90bc947e9299bdc3e3`
- Retrieved for Jiukong: 2026-09-23
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)

Jiukong retains the explicit character and multi-character word readings.
Jiukong does **not** copy or embed Rime's runtime, schema implementation,
composition logic, candidate ranking, OpenCC conversion data,
`jyut6ping3.maps`, or the upstream phrase-only dictionary. The latter has no
explicit Jyutping column and is intentionally not imported.

At runtime Jiukong parses the tab-separated character/readings and
word/reading-sequences after the YAML headers, validates Jyutping locally,
filters every output character through Jiukong's Taiwan Traditional CNS plane
1/2 repertoire, and applies Jiukong-owned matching and candidate presentation.
Multi-syllable matching accepts omitted or explicit 1–6 tone digits per
syllable. The source data remains attributable to the
Cantonese Computational Linguistics Infrastructure Development Workgroup
(CanCLID) and the Rime Cantonese project.

Upstream project: https://github.com/rime/rime-cantonese

License: https://creativecommons.org/licenses/by/4.0/
