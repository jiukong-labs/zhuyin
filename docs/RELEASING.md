# Public release

Jiukong Zhuyin is distributed outside the Mac App Store as a universal,
Developer ID-signed and Apple-notarized installer package. The package installs
`Jiukong Zhuyin.app` for all users at `/Library/Input Methods` and does not
automatically select an input source on anyone's behalf.

Apple's current requirements and command-line workflow are documented in
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

The release script deliberately has no unsigned public-release mode. Local
ad-hoc builds remain available through `scripts/install.sh`.

## Apple account preparation

Before the first release, the active Apple Developer Program team must have:

1. The explicit App ID `tw.idv.jiukong.inputmethod.zhuyin` with iCloud and
   CloudKit enabled.
2. The production container `iCloud.tw.idv.jiukong.inputmethod.zhuyin`, with
   its schema reviewed, tested, and deployed as described in `CLOUD_SYNC.md`.
3. A Developer ID Application certificate and a Developer ID Installer
   certificate, including their private keys.
4. A Developer ID provisioning profile for the App ID that authorizes its
   CloudKit entitlements.
5. App Store Connect API-key credentials accepted by Apple's notary service,
   or a `notarytool` keychain profile for a local release.

The provisioning profile is not optional: CloudKit is a restricted entitlement
and macOS expects a Developer ID profile to be embedded in the shipped app.
The export step explicitly selects the Production CloudKit environment.

## Local release

Install the two Developer ID identities and the Developer ID provisioning
profile in Xcode. Store notary credentials once in the login keychain, for
example:

```sh
xcrun notarytool store-credentials "jiukong-notary" \
  --key "/secure/path/AuthKey_KEYID.p8" \
  --key-id "KEYID" \
  --issuer "ISSUER-UUID"
```

Run the release from a clean checkout of the tag:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
DEVELOPER_ID_PROVISIONING_PROFILE="Jiukong Zhuyin Developer ID" \
NOTARY_KEYCHAIN_PROFILE="jiukong-notary" \
RELEASE_TAG="v0.1.0" \
./scripts/package-release.sh
```

The script refuses to overwrite an existing artifact. A successful run writes:

```text
dist/Jiukong-Zhuyin-0.1.0.pkg
dist/Jiukong-Zhuyin-0.1.0.pkg.sha256
```

Before returning success it verifies the stable bundle identifier, both CPU
architectures, Developer ID signature, Hardened Runtime, embedded provisioning
profile, installer signature, notarization ticket, and Gatekeeper assessment.

Before creating the tag, install the exact working build and run the local
source, unit, and installed-input preflight:

```sh
./scripts/install.sh
./scripts/run-release-preflight.sh
```

## GitHub release workflow

Create a protected GitHub Actions environment named `release`, then add these
environment secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Base64 of one password-protected P12 containing both Developer ID identities and private keys |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password of that P12 |
| `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` | Base64 of the Developer ID `.provisionprofile` |
| `NOTARY_KEY_P8_BASE64` | Base64 of the App Store Connect API private key |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | Team API issuer UUID |

Keep the environment protected with required reviewers. Never store a P12,
private key, profile, password, or decoded secret in the repository.

For each release:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`,
   regenerate the checked-in Xcode project, complete CI, install that exact
   build, and pass `scripts/run-release-preflight.sh`, including every default
   scenario defined by the [input behavior matrix](INPUT_BEHAVIOR_MATRIX.md).
2. Create and push the matching tag, such as `v0.1.0`.
3. Create a draft GitHub Release for that existing tag.
4. Run **Build signed release** and enter the tag.
5. Review the attached `.pkg`, checksum, and release notes before publishing
   the draft. The installed update checker ignores drafts, prereleases, and a
   release missing either exact asset name, so both artifacts must be present
   before publication.

The workflow will not create or publish a release. It only accepts an existing
draft whose tag is the checked-out commit. It reruns the test suite and
dictionary reproducibility check before importing signing credentials, then
uploads the signed package and checksum to that draft.

## Clean-machine acceptance

Before publishing, download the release asset through GitHub onto Macs that do
not have a development build registered. At minimum verify one Apple Silicon
Mac and, while x86_64 remains supported, one Intel Mac:

1. Installer and Gatekeeper report an identified developer without a bypass.
2. The app exists only at `/Library/Input Methods/Jiukong Zhuyin.app`.
3. After enabling 久空輸入法 in System Settings, normal composition,
   candidates, settings, learning, import, and export work.
4. CloudKit upload and restoration work between two Macs on the same test
   Apple Account, including offline edits and deletion tombstones.
5. Reinstalling the same package and then upgrading from the previous release
   preserve local user data.
6. `THIRD_PARTY_NOTICES.md`, `LICENSE`, and both source-verbatim MOE usage notes
   are present in the installed app's `Contents/Resources` directory.

The installed input-behavior gate is release-blocking. Record its command and
passing script count in the draft release notes; do not substitute a green
unit-test run for the real InputMethodKit acceptance path.

New input methods may require explicit approval in System Settings, and macOS
may require one sign-out/sign-in before the input source appears. Document that
normal platform behavior in every GitHub Release.
