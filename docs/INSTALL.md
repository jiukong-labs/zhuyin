# Install Jiukong Zhuyin

Jiukong Zhuyin requires macOS 13 or later. Its public installer contains both
Apple Silicon (`arm64`) and Intel (`x86_64`) code and installs the input method
for every user of the Mac.

## Install

1. Open the project's [GitHub Releases](https://github.com/jiukong-labs/zhuyin/releases)
   page and download `Jiukong-Zhuyin-<version>.pkg` and its adjacent
   `.pkg.sha256` file. Do not use GitHub's automatically generated source-code
   ZIP as an installer.
2. Optionally verify the download in Terminal from the download directory:

   ```sh
   shasum -a 256 -c Jiukong-Zhuyin-0.1.0.pkg.sha256
   ```

   Replace `0.1.0` with the downloaded version. The result must say `OK`.
3. Double-click the `.pkg`, confirm that macOS identifies the developer, and
   complete the installer. Administrator approval is required because the app
   is installed at `/Library/Input Methods/Jiukong Zhuyin.app`.
4. Installer stops the currently cached 久空 process while replacing the app.
   Save your work, then sign out of macOS and sign back in, or restart the Mac
   so every text service loads the installed version. The Installer completion
   screen also shows this reminder.
5. Open **System Settings > Keyboard**. Under **Text Input**, click **Edit…**,
   then **+**. Select **Traditional Chinese**, add **久空輸入法**, and approve
   macOS's input-method prompt if it appears.
6. Select 久空輸入法 from the menu-bar input menu. The installer never changes
   the active input source automatically.

If 久空輸入法 does not appear in System Settings after signing back in, repeat
step 5. This refreshes macOS's per-login input-source registration.

## Update

久空 automatically checks the project's latest published GitHub Release at
most once every 24 hours. It only accepts a stable release that contains both
the expected signed `.pkg` and adjacent `.pkg.sha256` asset. The request does
not include composition text, learned selections, or user phrases.

When a new version is available, its version appears under **Check for
Updates…** in the input-source menu and in the **Software Update** settings
pane. Choose **Download and Install** to let 久空 download the `.pkg` and its
checksum, verify SHA-256, the expected Developer ID Installer team, and
Gatekeeper acceptance, then open the verified package in macOS Installer.
The release-page button remains available as a manual fallback. Administrator
approval is still required because the package updates `/Library/Input
Methods`. It replaces the application bundle but preserves preferences,
learned selections, and user phrases under the current user's Library
directory. Installer stops the cached process before replacing the bundle and
once more afterward so the previous executable cannot keep running through the
update.

Do not keep a second development copy at
`~/Library/Input Methods/Jiukong Zhuyin.app`: two bundles with the same
identifier can make macOS register the wrong copy. Remove the development copy
with `scripts/uninstall.sh` before installing a public release.

After the update finishes, save your work, then sign out of macOS and sign back
in, or restart the Mac. This is the same full text-service refresh described in
install step 4.

## Remove

1. In **System Settings > Keyboard > Text Input > Edit…**, remove 久空輸入法
   from the enabled input sources.
2. In Finder choose **Go > Go to Folder…**, enter `/Library/Input Methods`, and
   move `Jiukong Zhuyin.app` to the Trash. macOS may request administrator
   approval.
3. Sign out and back in if the removed input method remains in the input menu.

Removing the app does not erase personal learning data. Use the input method's
Data settings before removal if you want to clear or export that data.

## Privacy and licenses

Composition and candidate lookup remain on the Mac. Optional CloudKit sync
uses the current Apple Account's private database for committed learning data
and explicitly saved user phrases. The project license, third-party notices,
and the source-verbatim Ministry of Education usage notes are included in the
installed application bundle and remain available in the source repository.
