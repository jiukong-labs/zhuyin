# Rime Cantonese Jyutping character data

This directory contains the one third-party Cantonese dataset explicitly
approved for Jiukong's Cantonese input mode.

- Upstream: `rime/rime-cantonese`
- File: `jyut6ping3.chars.dict.yaml`
- Pinned commit: `259f0e48bba840c3a2e0d117539e96937f3d89bc`
- Upstream data version: `2026.08.10`
- Upstream blob SHA: `f31eb5e66b0f26b6427306c514aa42d396c13a97`
- Retrieved for Jiukong: 2026-09-23
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)

Only the character-to-Jyutping file is retained. Jiukong does **not** copy or
embed Rime's runtime, schema implementation, composition logic, candidate
ranking, OpenCC conversion data, `jyut6ping3.maps`, or the upstream words and
phrase dictionaries in this milestone.

At runtime Jiukong parses the tab-separated character/readings after the YAML
header, validates Jyutping spellings locally, filters output through Jiukong's
Taiwan Traditional CNS plane 1/2 repertoire, and applies Jiukong-owned
candidate presentation behavior. The source data remains attributable to the
Cantonese Computational Linguistics Infrastructure Development Workgroup
(CanCLID) and the Rime Cantonese project.

Upstream project: https://github.com/rime/rime-cantonese

License: https://creativecommons.org/licenses/by/4.0/
