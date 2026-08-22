# Jiukong Zhuyin project instructions

## Original implementation policy

Jiukong Zhuyin is a first-party, independently designed project. This policy
applies to every future change in this repository.

- Product code, input-method behavior, composition algorithms, candidate
  ranking, learning logic, database formats, UI, and the built-in phrase
  lexicon must be designed and implemented specifically for this project.
- Do not copy, translate, port, mechanically rewrite, or derive implementation
  code or language data from another input method, dictionary, corpus, or
  frequency list.
- Do not import a third-party runtime dependency, source package, model, or
  dataset unless the user explicitly changes this policy for that exact item.
- When outside research is necessary, use platform documentation and formal
  standards to understand interfaces or compatibility requirements; do not use
  another input method's implementation as a design template.
- New built-in phrase entries must be manually authored and reviewed in this
  repository. They must not be bulk-generated from or compared against an
  outside lexicon.
- If a requested feature cannot be completed without relaxing this policy,
  stop and explain the limitation instead of silently adding outside material.

Existing, documented exceptions are limited to Apple's platform SDKs and
system libraries, development-only tooling, and the pinned official CNS11643
character/phonetic standard data already listed in `THIRD_PARTY_NOTICES.md`.
Do not broaden these exceptions without explicit user approval.
