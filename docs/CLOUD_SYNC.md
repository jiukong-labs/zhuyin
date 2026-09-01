# iCloud sync

Jiukong keeps `user.sqlite` as the runtime source of truth for candidate lookup.
No keystroke, composition update, or candidate query waits for CloudKit. The
sync layer operates on individual character-learning and user-phrase records
in the user's private CloudKit database; it never places the live SQLite file
inside iCloud Drive.

## Behavior

- Sync is enabled by default and can be disabled in Settings → Data.
- Turning sync off cancels the active fetch or save and ignores any callback
  that arrives after cancellation. Local pending mutations remain journaled.
- Jiukong stores a one-way digest of the CloudKit account identifier that was
  authorized to sync. When macOS reports an Apple Account change, Jiukong
  cancels the active transfer and verifies that identifier before touching
  local data. Cache-reset notifications after an app update or reinstall keep
  sync enabled when the account is unchanged; a genuinely different account
  turns sync off and must be explicitly authorized.
- App startup performs an initial fetch. Activating the input method also
  checks for remote changes, rate-limited to once per 15 minutes.
- Successful local mutations are persisted to
  `~/Library/Application Support/JiukongZhuyin/cloud-sync-state.json` and
  uploaded after a two-second debounce. The journal is mode `0600` inside the
  existing mode `0700` application-support directory.
- A fresh Mac applies remote records before migrating any pre-existing local
  data. This prevents an old local row from overriding a cloud deletion.
- Counts and last-used timestamps retain the larger/newer value, phrase
  creation retains the earlier value, and a pending local pin decision wins a
  simultaneous remote pin decision. CloudKit change tags prevent a stale save
  from silently overwriting a record changed after the fetch; failed saves
  remain pending and retry later.
- Deletions are saved as records with a tombstone flag instead of physically
  deleting the CloudKit record. This lets an offline Mac learn that an entry
  was removed and prevents reinstall restoration from resurrecting it.
- CloudKit record names contain only a versioned SHA-256 digest of the logical
  identity. Text, ordered readings, count, timestamps, and pin values use
  `CKRecord.encryptedValues`.

The learning custom private-database zone is `JiukongUserLearning`; its record
type is `JKUserLearning`. The local SQLite schema remains at version 2 because
CloudKit state is deliberately stored separately.

## Cursor appearance preferences

The same opt-in iCloud setting also synchronizes cursor-indicator appearance.
UserDefaults remains the live local source of truth, so typing and settings
never wait for CloudKit. Synchronized fields include the Chinese and English
labels and colors, composition-dot color and show/animate switches, text size,
placement, tracking, and Caps Lock indicator appearance.

Appearance preferences use a separate custom zone, `JiukongPreferences`, and
record type, `JKPreference`. Each known preference has its own record so an
older app cannot overwrite fields introduced by a newer version. The value is
stored through `CKRecord.encryptedValues`; the schema version, opaque
preference key, modification time, and monotonic revision remain ordinary
record metadata. Last-write-wins resolution compares modification time, then
revision, with a deterministic value tie-breaker.

Local sync state is stored separately at
`~/Library/Application Support/JiukongZhuyin/cloud-preferences-state.json`
with the same `0600` file protection. Offline changes remain pending and retry
later. Malformed or unsupported remote fields are ignored individually rather
than replacing valid local settings, and remote changes apply immediately
without relaunching the input method.

Both zones use the private database in container
`iCloud.tw.idv.jiukong.inputmethod.zhuyin`.

## Failure behavior

No iCloud account, no network, missing entitlements, quota or service errors,
and CloudKit conflicts never disable local learning, local appearance settings,
or typing. The Data pane shows the current status and offers an immediate
retry. Pending local changes remain in their respective journals until a
complete save succeeds.

JSON export/import remains the provider-independent backup path. An exported
JSON file is not encrypted and should still be handled as personal data.

## Signing and production deployment

The repository declares the CloudKit entitlement in
`Resources/JiukongZhuyin.entitlements`, but its checked-in local-development
configuration still uses ad-hoc signing. An ad-hoc build can compile and run,
but it cannot access the production iCloud container.

Before shipping:

1. Use an active Apple Developer Program team that controls the stable bundle
   identifier `tw.idv.jiukong.inputmethod.zhuyin`.
2. Create or assign the iCloud container
   `iCloud.tw.idv.jiukong.inputmethod.zhuyin` to that App ID, enable CloudKit,
   and build with the matching development/distribution provisioning profile.
   Set the user-defined Xcode build setting `JIUKONG_CLOUDKIT_ENTITLEMENTS` to
   `Resources/JiukongZhuyin.entitlements`; `CODE_SIGN_ENTITLEMENTS` expands from
   this setting and intentionally stays empty for the repository's ad-hoc
   local build.
3. Run a signed development build while logged into a test iCloud account to
   create and exercise the development schema.
4. In CloudKit Console, verify the encrypted fields and deploy the schema to
   production. CloudKit production schema changes are additive, so names and
   encryption choices must be reviewed before this step.
5. Verify upload on one Mac, restore on a clean second Mac using the same Apple
   Account, offline mutation upload, unpinning, individual deletion, and clear
   operations before release.

Unit tests use in-memory transports and cover learning restore, initial upload,
tombstones, pending local precedence, exact unpinning, failed-save retention,
disabled and cancelled sync, real and spurious Apple Account changes, stable
opaque identities, private journal persistence, preference last-write-wins,
offline retry, malformed preference records, and forward schema compatibility.
They do not substitute for the signed two-Mac CloudKit acceptance run above.
