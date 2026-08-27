# Contributing

Jiukong Zhuyin treats its documented keyboard behavior as a compatibility
contract. Before changing input events, language modes, composition,
candidates, punctuation, or keyboard arrangements, read
`docs/INPUT_BEHAVIOR_MATRIX.md` and identify every affected row.

Keep product behavior changes focused. Do not combine them with release
automation, signing, generated assets, data changes, or unrelated refactors in
one commit. Commit messages must name the behavior being changed rather than
using only a date or batch label.

Every user-visible behavior change needs all four forms of evidence in the
same pull request:

1. product documentation;
2. pure unit tests for routing and state;
3. an installed Acceptance Harness scenario for the real InputMethodKit path;
4. an updated regression-matrix entry.

Run unit tests in CI and run the installed acceptance gate locally before a
release. The harness needs Accessibility permission and therefore cannot run
inside GitHub-hosted CI, but CI verifies that every release-blocking scenario
is still present in its default manifest.

After installing the exact build under review, the release gate has one entry
point:

```sh
./scripts/run-release-preflight.sh
```

Protect `main` in GitHub with pull requests and required passing checks. Do not
allow force pushes or branch deletion. Repository files can document and
review this policy, but an administrator must enforce those two restrictions
in the GitHub ruleset or branch-protection settings.
