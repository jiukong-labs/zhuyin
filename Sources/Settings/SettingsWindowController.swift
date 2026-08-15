import AppKit

/// The single settings window shared by every InputMethodKit client.
///
/// The input method is a background-only agent, so the window is created lazily
/// and the process is activated explicitly before it is ordered front. Like the
/// candidate window and the mode HUD, it is only ever used from the main thread.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let preferences: PreferencesController
    private let learning: UserLearningService

    private var window: NSWindow?
    private var shiftPopUpButton: NSPopUpButton?
    private var automaticLearningButton: NSButton?

    private static let shiftOptions: [(title: String, value: ShiftKeyPreference)] = [
        ("左右 Shift 皆可", .both),
        ("只用左 Shift", .left),
        ("只用右 Shift", .right),
        ("關閉 Shift 切換", .disabled),
    ]

    init(
        preferences: PreferencesController = .shared,
        learning: UserLearningService = .shared
    ) {
        self.preferences = preferences
        self.learning = learning
        super.init()
    }

    func show() {
        let window = existingOrNewWindow()
        reloadControls()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the window object so the next open restores the same position.
        NSApp.deactivate()
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "久空輸入法設定"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        window.center()
        self.window = window
        return window
    }

    private func makeContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(
            top: 20,
            left: 24,
            bottom: 20,
            right: 24
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeLanguageSection())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeLearningSection())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeDataSection())

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: container.bottomAnchor
            ),
        ])
        return container
    }

    private func makeLanguageSection() -> NSView {
        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in Self.shiftOptions {
            popUpButton.addItem(withTitle: option.title)
        }
        popUpButton.target = self
        popUpButton.action = #selector(shiftPreferenceDidChange(_:))
        shiftPopUpButton = popUpButton

        return makeSection(
            title: "中英文切換",
            controls: [popUpButton],
            note: "單獨按一下所選的 Shift 鍵切換中英文；按住 Shift 搭配其他鍵不會切換。"
        )
    }

    private func makeLearningSection() -> NSView {
        let checkbox = NSButton(
            checkboxWithTitle: "自動學習已提交的選字與詞頻",
            target: self,
            action: #selector(automaticLearningDidChange(_:))
        )
        automaticLearningButton = checkbox

        return makeSection(
            title: "學習",
            controls: [checkbox],
            note: "關閉後不再累積新的使用次數，既有紀錄仍會影響排序，Shift 造詞也仍可使用。"
        )
    }

    private func makeDataSection() -> NSView {
        let clearCharacters = NSButton(
            title: "清除選字紀錄…",
            target: self,
            action: #selector(clearCharacterLearning(_:))
        )
        let clearPhrases = NSButton(
            title: "清除使用者詞…",
            target: self,
            action: #selector(clearUserPhrases(_:))
        )
        let clearAll = NSButton(
            title: "清除全部…",
            target: self,
            action: #selector(clearAllUserData(_:))
        )

        let row = NSStackView(views: [clearCharacters, clearPhrases, clearAll])
        row.orientation = .horizontal
        row.spacing = 10

        return makeSection(
            title: "使用者資料",
            controls: [row],
            note: "資料只存在這台 Mac，清除後無法復原。"
        )
    }

    private func makeSection(
        title: String,
        controls: [NSView],
        note: String
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let noteLabel = NSTextField(wrappingLabelWithString: note)
        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.preferredMaxLayoutWidth = 400

        let stack = NSStackView(views: [titleLabel] + controls + [noteLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 412).isActive = true
        return separator
    }

    private func reloadControls() {
        let current = preferences.current
        if let index = Self.shiftOptions.firstIndex(
            where: { $0.value == current.shiftKeyPreference }
        ) {
            shiftPopUpButton?.selectItem(at: index)
        }
        automaticLearningButton?.state =
            current.automaticLearningEnabled ? .on : .off
    }

    @objc private func shiftPreferenceDidChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard Self.shiftOptions.indices.contains(index) else {
            return
        }
        preferences.update {
            $0.shiftKeyPreference = Self.shiftOptions[index].value
        }
    }

    @objc private func automaticLearningDidChange(_ sender: NSButton) {
        preferences.update {
            $0.automaticLearningEnabled = sender.state == .on
        }
    }

    @objc private func clearCharacterLearning(_ sender: Any?) {
        performClear(
            message: "清除全部選字紀錄？",
            informative: "會刪除所有單字的使用次數與置頂狀態，使用者詞會保留。"
        ) { [learning] in
            learning.clearCharacterLearning()
        }
    }

    @objc private func clearUserPhrases(_ sender: Any?) {
        performClear(
            message: "清除全部使用者詞？",
            informative: "會刪除所有自己造的詞與其注音，選字紀錄會保留。"
        ) { [learning] in
            learning.clearUserPhrases()
        }
    }

    @objc private func clearAllUserData(_ sender: Any?) {
        performClear(
            message: "清除全部使用者資料？",
            informative: "會刪除所有選字紀錄與使用者詞，排序會回到 CNS 原始順序。"
        ) { [learning] in
            learning.clearAllUserData()
        }
    }

    private func performClear(
        message: String,
        informative: String,
        operation: () -> Bool
    ) {
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = message
        confirmation.informativeText = informative + "此操作無法復原。"
        confirmation.addButton(withTitle: "清除")
        confirmation.addButton(withTitle: "取消")
        guard confirmation.runModal() == .alertFirstButtonReturn else {
            return
        }

        guard operation() else {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "無法清除使用者資料"
            failure.informativeText = "資料庫目前無法寫入，既有資料仍然保留。"
            failure.addButton(withTitle: "好")
            failure.runModal()
            return
        }
    }
}
