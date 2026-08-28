import AppKit

enum UpdatePrompt {
    private static var progressAlert: NSAlert?

    static func present(_ state: UpdateCheckState) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        switch state {
        case let .updateAvailable(release, installedVersion):
            alert.messageText = "有新版久空輸入法"
            alert.informativeText =
                "目前版本為 \(installedVersion)，最新版本為 \(release.version)。久空會下載並驗證安裝套件，再自動開啟 macOS 安裝程式；安裝到 /Library/Input Methods 仍需管理員授權。"
            alert.addButton(withTitle: "下載並安裝")
            alert.addButton(withTitle: "開啟發布頁面")
            alert.addButton(withTitle: "稍後")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                prepareAndOpenInstaller(for: release)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(release.pageURL)
            default:
                break
            }
        case let .upToDate(installedVersion):
            alert.messageText = "久空輸入法已是最新版本"
            alert.informativeText = "目前版本：\(installedVersion)"
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case let .failed(_, message):
            alert.messageText = "無法檢查更新"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .idle, .checking:
            break
        }
    }

    private static func prepareAndOpenInstaller(for release: UpdateRelease) {
        if let progressAlert {
            NSApp.activate(ignoringOtherApps: true)
            progressAlert.window.makeKeyAndOrderFront(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = "正在準備久空輸入法 \(release.version)"
        alert.informativeText = "正在下載並驗證安裝套件，完成後會自動開啟 macOS 安裝程式。"

        let progress = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 18))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        alert.accessoryView = progress

        progressAlert = alert
        NSApp.activate(ignoringOtherApps: true)
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)

        UpdatePackagePreparer.shared.prepare(release: release) { result in
            progress.stopAnimation(nil)
            alert.window.close()
            progressAlert = nil

            switch result {
            case let .success(packageURL):
                guard NSWorkspace.shared.open(packageURL) else {
                    presentInstallationFailure(
                        message: "無法開啟 macOS 安裝程式。",
                        release: release
                    )
                    return
                }
            case let .failure(error):
                presentInstallationFailure(
                    message: error.localizedDescription,
                    release: release
                )
            }
        }
    }

    private static func presentInstallationFailure(
        message: String,
        release: UpdateRelease
    ) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "無法準備更新"
        alert.informativeText =
            "\(message)\n\n沒有執行任何安裝。您仍可前往 GitHub 發布頁面手動下載。"
        alert.addButton(withTitle: "開啟發布頁面")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }
}
