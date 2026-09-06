import AppKit

enum UpdatePrompt {
    private static var progressWindow: NSWindow?

    static func present(_ state: UpdateCheckState) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        switch state {
        case let .updateAvailable(release, installedVersion):
            alert.messageText = "有新版久空輸入法"
            alert.informativeText =
                "目前版本為 \(installedVersion)，最新版本為 \(release.version)。久空會下載並驗證安裝套件，再自動開啟 macOS 安裝程式；安裝時會停止目前的久空輸入法程序，請先儲存工作。安裝到 /Library/Input Methods 仍需管理員授權。"
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
        if let progressWindow {
            NSApp.activate(ignoringOtherApps: true)
            progressWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = makeProgressWindow(
            title: "正在準備久空輸入法 \(release.version)",
            message: "正在下載並驗證安裝套件，完成後會自動開啟 macOS 安裝程式。"
        )

        progressWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)

        UpdatePackagePreparer.shared.prepare(release: release) { result in
            progressIndicator(in: window)?.stopAnimation(nil)
            window.close()
            progressWindow = nil

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

    /// Builds the modeless preparation window.
    ///
    /// This deliberately does not use `NSAlert`. An alert lays its panel out
    /// only while it runs a modal session or sheet, so ordering `alert.window`
    /// in directly shows the untouched template instead: an unlocalized
    /// `<Do not show this message again>` suppression checkbox, title-less
    /// buttons, and no accessory view at all. Download progress must stay
    /// modeless, so the same content is assembled as a plain panel.
    static func makeProgressWindow(title: String, message: String) -> NSWindow {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64)
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        titleLabel.preferredMaxLayoutWidth = progressWindowContentWidth

        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        messageLabel.preferredMaxLayoutWidth = progressWindowContentWidth

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)

        let content = NSStackView(
            views: [icon, titleLabel, messageLabel, progress]
        )
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(
            top: 20,
            left: 20,
            bottom: 20,
            right: 20
        )
        content.setCustomSpacing(6, after: titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(
                equalToConstant: progressWindowContentWidth
            ),
            messageLabel.widthAnchor.constraint(
                equalToConstant: progressWindowContentWidth
            ),
            progress.widthAnchor.constraint(
                equalToConstant: progressWindowContentWidth
            )
        ])

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.contentView = content
        window.setContentSize(
            content.fittingSize
        )
        return window
    }

    /// The window's own progress indicator, so preparation can stop its
    /// animation before the window closes.
    static func progressIndicator(in window: NSWindow) -> NSProgressIndicator? {
        window.contentView?.subviews.compactMap {
            $0 as? NSProgressIndicator
        }.first
    }

    private static let progressWindowContentWidth: CGFloat = 280

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
