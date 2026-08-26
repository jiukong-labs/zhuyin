# Jiukong Zhuyin project instructions

## Original implementation policy

Jiukong Zhuyin is a first-party, independently designed project. This policy
applies to every future change in this repository.

- Product code, input-method behavior, composition algorithms, candidate
  ranking, learning logic, database formats, UI, and the first-party phrase
  lexicon must be designed and implemented specifically for this project.
- Outside the closed, documented exceptions below, do not copy, translate,
  port, mechanically rewrite, or derive implementation code or language data
  from another input method, dictionary, corpus, or frequency list.
- Do not import a third-party runtime dependency, source package, model, or
  dataset unless the user explicitly changes this policy for that exact item.
- When outside research is necessary, use platform documentation and formal
  standards to understand interfaces or compatibility requirements; do not use
  another input method's implementation as a design template.
- New first-party phrase entries must be manually authored and reviewed in
  this repository. They must not be bulk-generated from or compared against
  an outside lexicon. The separately stored, approved government phrase
  datasets listed below must remain attributable, source-verbatim data and
  must not be presented as first-party or AI-authored content.
- If a requested feature cannot be completed without relaxing this policy,
  stop and explain the limitation instead of silently adding outside material.

Existing, documented exceptions are limited to:

- Apple's platform SDKs and system libraries;
- development-only tooling;
- the pinned official CNS11643 character/phonetic standard data;
- the pinned Ministry of Education common and semi-common standard character
  tables, used only as coarse candidate-ranking tiers; and
- the pinned headword-and-reading extracts of the Ministry of Education's
  《成語典》 2020 and 《重編國語辭典修訂本》 datasets, used only for the
  separately identified government-sourced four-character phrase candidates.

The exact sources, transformations, versions, and licenses for these
exceptions are listed in `THIRD_PARTY_NOTICES.md` and their `Data/*/README.md`
files. Government-sourced phrase entries must remain excluded from
first-party phrase-attestation ranking signals. Do not add another dataset,
expand the retained fields or entry scope, or broaden these exceptions without
explicit user approval.
