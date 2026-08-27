## What changed

Describe one focused product or infrastructure change and why it is needed.

## User-visible behavior

- [ ] No user-visible input behavior changed.
- [ ] User-visible behavior changed; the relevant documentation, unit tests,
      and `docs/INPUT_BEHAVIOR_MATRIX.md` were updated together.

## Verification

- [ ] Debug unit tests pass.
- [ ] Acceptance Harness builds and the release-blocking matrix check passes.
- [ ] I installed this exact build and ran `./scripts/run-acceptance.sh`, or
      documented why installed acceptance is not applicable.
- [ ] If keyboard layout or shared event routing changed, I also ran the
      opt-in `eten` and `ibm` acceptance scripts.

## History safety

- [ ] The change is focused and reviewable; unrelated product and release
      infrastructure changes are not mixed together.
- [ ] This change does not require rewriting or force-pushing `main`.
