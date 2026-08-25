# Cloud sync

Jiukong Zhuyin can back up learned character choices and exact user phrases to
the signed-in user's CloudKit private database. Input, composition, candidate
lookup, and ranking remain local and never wait for the network.

## Data boundary

The cloud payload is the same validated, versioned `UserDataArchive` JSON used
by manual export. It contains:

- character, canonical reading, selection count, latest selection time, and pin;
- user phrase, ordered canonical readings, selection count, creation and latest
  use times, and pin.

The built-in dictionary, bundled phrase lexicon, application preferences,
surrounding document text, and keystrokes are not uploaded. The project has no
application server; CloudKit stores the record in the user's private database.

## Apple configuration

- App ID: `tw.idv.jiukong.inputmethod.zhuyin`
- iCloud container: `iCloud.tw.idv.jiukong.inputmethod.zhuyin`
- Entitlements: `Resources/JiukongZhuyin.entitlements`
- Record type: `JiukongUserLearningSnapshot`
- Deterministic record name: `current`
- Asset field: `payload`

The Xcode target uses Automatic Signing and the project's Apple Development
team. CloudKit and the container must remain selected in Signing & Capabilities.
The first successful development sync creates the record type and fields in the
development schema. Before distributing a production-signed build, inspect the
schema in CloudKit Console and deploy it from Development to Production.

## Synchronization behavior

Cloud sync defaults off and starts only after the user enables it in the
**資料** tab. At process startup and when the user presses **立即同步**, the
service:

1. checks that a private iCloud database is available;
2. fetches and validates the remote archive when one exists;
3. merges it transactionally into local SQLite;
4. exports the merged local state and saves it as a `CKAsset`;
5. refetches and retries up to twice if CloudKit reports a record conflict.

Counts and timestamps use the larger/newer value, phrase creation keeps the
earlier time, and pins form a union. This is idempotent, so repeating a restore
does not double counts. Successful local changes are debounced for three
seconds before syncing. Explicit deletes, clears, and unpins replace the remote
snapshot so old cloud state is not immediately restored; a different Mac that
was offline can still later contribute its own newer merge.

If iCloud is unavailable or a transfer fails, the local SQLite data and input
path continue to work. The settings window reports the state and allows a
manual retry.

When macOS reports that the signed-in iCloud Apple Account changed, Jiukong
immediately cancels the current transfer and turns synchronization off. The
user must explicitly enable it again before any local archive can be merged or
uploaded to the new account.

## Reinstall restoration

On a new or reinstalled Mac:

1. sign in to macOS with the same iCloud Apple Account;
2. install a build signed for the same App ID and container;
3. start Jiukong Zhuyin or open its settings;
4. explicitly enable **使用 iCloud 同步選字與使用者詞**.

The first synchronization merges the private snapshot into the newly created
local database. The **資料** tab then shows the last successful sync time.

## Verification

Confirm the built application carries the expected entitlements:

```sh
codesign -d --entitlements :- \
  "$HOME/Library/Input Methods/Jiukong Zhuyin.app"
```

The output must include `com.apple.developer.icloud-services` with `CloudKit`
and `com.apple.developer.icloud-container-identifiers` with the Jiukong
container. In CloudKit Console, select the same container and Development
environment; after the first successful sync, the private database contains the
`JiukongUserLearningSnapshot/current` record.

For unsigned or CI-only verification, override the restricted entitlement and
signing settings as the GitHub Actions workflow does. Such a build can test the
merge policy but cannot access CloudKit at runtime.
