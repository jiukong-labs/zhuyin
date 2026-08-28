import AppKit

enum UpdatePrompt {
    static func present(_ state: UpdateCheckState) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        switch state {
        case let .updateAvailable(release, installedVersion):
            alert.messageText = "有新版久空輸入法"
            alert.informativeText =
                "目前版本為 \(installedVersion)，最新版本為 \(release.version)。下載後請開啟安裝套件；因為輸入法安裝在 /Library/Input Methods，macOS 會要求管理員授權。"
            alert.addButton(withTitle: "開啟下載頁面")
            alert.addButton(withTitle: "稍後")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
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
}
