# iCloud learning sync

Jiukong keeps `user.sqlite` as the runtime source of truth for candidate lookup.
No keystroke, composition update, or candidate query waits for CloudKit. The
sync layer operates on individual character-learning and user-phrase records
in the user's private CloudKit database; it never places the live SQLite file
inside iCloud Drive.

## Behavior

- Sync is enabled by default and can be disabled in Settings → Data.
- Turning sync off cancels the active fetch or save and ignores any callback
  that arrives after cancellation. Local pending mutations remain journaled.
- When macOS reports an Apple Account change, Jiukong cancels the active
  transfer and turns sync off. The user must explicitly enable it again for
  the newly active account.
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

The custom private-database zone is `JiukongUserLearning`; the record type is
`JKUserLearning`; and the container identifier is
`iCloud.tw.idv.jiukong.inputmethod.zhuyin`. The local SQLite schema remains at
version 2 because CloudKit state is deliberately stored separately.

## Failure behavior

No iCloud account, no network, missing entitlements, quota or service errors,
and CloudKit conflicts never disable local learning or typing. The Data pane
shows the current status and offers an immediate retry. Pending local changes
remain in the journal until a complete save succeeds.

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

Unit tests use an in-memory transport and cover restore, initial upload,
tombstones, pending local precedence, exact unpinning, failed-save retention,
disabled and cancelled sync, Apple Account changes, stable opaque identities,
and private journal persistence. They do not substitute for the signed two-Mac
CloudKit acceptance run above.
