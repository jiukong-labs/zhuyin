import AppKit
import UniformTypeIdentifiers

/// The single settings window shared by every InputMethodKit client.
///
/// The input method is a background-only agent, so the window is created lazily
/// and the process is activated explicitly before it is ordered front. Like the
/// candidate window and the mode HUD, it is only ever used from the main thread.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let preferences: PreferencesController
    private let learning: UserLearningService

    private let characterList: UserDataListController
    private let phraseList: UserDataListController
    private let cursorIndicatorSettings: CursorIndicatorSettingsController

    private var window: NSWindow?
    private var shiftPopUpButton: NSPopUpButton?
    private var arrangementPopUpButton: NSPopUpButton?
    private var automaticLearningButton: NSButton?
    private var iCloudSyncButton: NSButton?
    private var cloudSyncStatusLabel: NSTextField?
    private var showsRareCandidatesButton: NSButton?

    private static let arrangements = ZhuyinKeyboardArrangement.allCases

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
        characterList = UserDataListController(
            kind: .characters,
            learning: learning
        )
        phraseList = UserDataListController(kind: .phrases, learning: learning)
        cursorIndicatorSettings = CursorIndicatorSettingsController(
            preferences: preferences
        )
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudSyncStatusDidChange(_:)),
            name: UserDataCloudSyncCoordinator.statusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudSyncDidApplyRemoteChanges(_:)),
            name: UserDataCloudSyncCoordinator.didApplyRemoteChangesNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        let window = existingOrNewWindow()
        reloadControls()
        reloadLists()
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
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
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        for (label, view) in [
            ("一般", makeGeneralView()),
            ("游標指示器", cursorIndicatorSettings.makeView()),
            ("使用者詞", phraseList.makeView()),
            ("選字紀錄", characterList.makeView()),
            ("資料", makeDataView()),
        ] {
            let item = NSTabViewItem(identifier: label)
            item.label = label
            item.view = view
            tabView.addTabViewItem(item)
        }

        let container = NSView()
        container.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: 12
            ),
            tabView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -12
            ),
            tabView.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: 12
            ),
            tabView.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -12
            ),
        ])
        return container
    }

    private func makeGeneralView() -> NSView {
        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in Self.shiftOptions {
            popUpButton.addItem(withTitle: option.title)
        }
        popUpButton.target = self
        popUpButton.action = #selector(shiftPreferenceDidChange(_:))
        shiftPopUpButton = popUpButton

        let shiftToggleLabel = NSTextField(labelWithString: "中英文切換：")
        let shiftToggleRow = NSStackView(views: [
            shiftToggleLabel,
            popUpButton,
        ])
        shiftToggleRow.orientation = .horizontal
        shiftToggleRow.alignment = .centerY
        shiftToggleRow.spacing = 8

        let optionShortcutLabel = NSTextField(
            wrappingLabelWithString:
                "⌥ Option：單獨按下不執行久空功能；Option 組合鍵交由目前 App 處理。"
        )
        optionShortcutLabel.preferredMaxLayoutWidth =
            SettingsPaneBuilder.contentWidth

        let checkbox = NSButton(
            checkboxWithTitle: "自動學習已提交的選字與詞頻",
            target: self,
            action: #selector(automaticLearningDidChange(_:))
        )
        automaticLearningButton = checkbox

        let rareCandidatesCheckbox = NSButton(
            checkboxWithTitle: "顯示罕用字、異體字與其他 CNS 字面",
            target: self,
            action: #selector(showsRareCandidatesDidChange(_:))
        )
        showsRareCandidatesButton = rareCandidatesCheckbox

        let arrangementButton = NSPopUpButton(frame: .zero, pullsDown: false)
        for arrangement in Self.arrangements {
            arrangementButton.addItem(withTitle: arrangement.localizedName)
        }
        arrangementButton.target = self
        arrangementButton.action = #selector(arrangementDidChange(_:))
        arrangementPopUpButton = arrangementButton

        return SettingsPaneBuilder.pane(
            sections: [
                SettingsPaneBuilder.section(
                    title: "注音鍵盤配置",
                    controls: [arrangementButton],
                    note: "與目前選用的英文字母鍵盤配置無關。切換時會先送出尚未完成的組字。"
                ),
                SettingsPaneBuilder.section(
                    title: "快捷鍵",
                    controls: [shiftToggleRow, optionShortcutLabel],
                    note: "單獨按一下所選的 Shift 鍵切換中英文；按住 Shift 搭配其他鍵不會切換。正在組字時使用 Option 組合鍵，久空會先完成目前組字。"
                ),
                SettingsPaneBuilder.section(
                    title: "學習",
                    controls: [checkbox],
                    note: "關閉後不再累積新的使用次數，既有紀錄仍會影響排序，Shift 造詞也仍可使用。"
                ),
                SettingsPaneBuilder.section(
                    title: "候選字範圍",
                    controls: [rareCandidatesCheckbox],
                    note: "預設只顯示 CNS 第 1、2 字面的常用與次常用字。開啟後才加入第 3 字面以後的罕用字、異體字與其他專門用字；字型缺字仍會略過。"
                ),
            ]
        )
    }

    private func makeDataView() -> NSView {
        let syncCheckbox = NSButton(
            checkboxWithTitle: "使用 iCloud 自動同步選字與使用者詞",
            target: self,
            action: #selector(iCloudSyncDidChange(_:))
        )
        iCloudSyncButton = syncCheckbox

        let syncNowButton = makeButton(
            "立即同步",
            action: #selector(synchronizeCloudNow(_:))
        )
        let statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = SettingsPaneBuilder.contentWidth
        cloudSyncStatusLabel = statusLabel

        let transferRow = NSStackView(views: [
            makeButton("匯出…", action: #selector(exportUserData(_:))),
            makeButton("匯入…", action: #selector(importUserData(_:))),
        ])
        transferRow.orientation = .horizontal
        transferRow.spacing = 10

        let clearRow = NSStackView(views: [
            makeButton("清除選字紀錄…", action: #selector(clearCharacterLearning(_:))),
            makeButton("清除使用者詞…", action: #selector(clearUserPhrases(_:))),
            makeButton("清除全部…", action: #selector(clearAllUserData(_:))),
        ])
        clearRow.orientation = .horizontal
        clearRow.spacing = 10

        return SettingsPaneBuilder.pane(
            sections: [
                SettingsPaneBuilder.section(
                    title: "iCloud 同步",
                    controls: [syncCheckbox, syncNowButton, statusLabel],
                    note: "使用同一個 Apple Account 的 Mac 會自動合併學習資料。輸入仍使用本機資料庫；沒有網路或 iCloud 暫時無法使用時，不會影響打字。同步欄位使用 CloudKit 加密值。"
                ),
                SettingsPaneBuilder.section(
                    title: "匯出與匯入",
                    controls: [transferRow],
                    note: "匯出為 JSON 檔。匯入會與現有資料合併：次數與時間取較大者，置頂取聯集，重複匯入同一個檔案不會重複累加。"
                ),
                SettingsPaneBuilder.section(
                    title: "清除",
                    controls: [clearRow],
                    note: "清除會同步到 iCloud，避免其他 Mac 或重灌後把舊資料恢復。"
                ),
            ]
        )
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func reloadControls() {
        let current = preferences.current
        if let index = Self.shiftOptions.firstIndex(
            where: { $0.value == current.shiftKeyPreference }
        ) {
            shiftPopUpButton?.selectItem(at: index)
        }
        if let index = Self.arrangements.firstIndex(
            of: current.keyboardArrangement
        ) {
            arrangementPopUpButton?.selectItem(at: index)
        }
        automaticLearningButton?.state =
            current.automaticLearningEnabled ? .on : .off
        iCloudSyncButton?.state = current.iCloudSyncEnabled ? .on : .off
        showsRareCandidatesButton?.state =
            current.showsRareCandidates ? .on : .off
        reloadCloudSyncStatus()
        cursorIndicatorSettings.reload()
    }

    private func reloadLists() {
        characterList.reload()
        phraseList.reload()
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

    @objc private func arrangementDidChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard Self.arrangements.indices.contains(index) else {
            return
        }
        preferences.update {
            $0.keyboardArrangement = Self.arrangements[index]
        }
    }

    @objc private func automaticLearningDidChange(_ sender: NSButton) {
        preferences.update {
            $0.automaticLearningEnabled = sender.state == .on
        }
    }

    @objc private func iCloudSyncDidChange(_ sender: NSButton) {
        preferences.update {
            $0.iCloudSyncEnabled = sender.state == .on
        }
        learning.cloudSyncPreferenceDidChange()
        reloadCloudSyncStatus()
    }

    @objc private func synchronizeCloudNow(_ sender: Any?) {
        learning.synchronizeCloudNow()
        reloadCloudSyncStatus()
    }

    @objc private func cloudSyncStatusDidChange(_ notification: Notification) {
        reloadCloudSyncStatus()
    }

    @objc private func cloudSyncDidApplyRemoteChanges(
        _ notification: Notification
    ) {
        reloadLists()
        reloadCloudSyncStatus()
    }

    @objc private func showsRareCandidatesDidChange(_ sender: NSButton) {
        preferences.update {
            $0.showsRareCandidates = sender.state == .on
        }
    }

    @objc private func exportUserData(_ sender: Any?) {
        guard let archive = learning.exportArchive() else {
            report(
                failure: "無法讀取使用者資料",
                informative: "資料庫目前無法讀取，沒有寫出任何檔案。"
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.exportFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try archive.encoded().write(to: url, options: .atomic)
        } catch {
            report(
                failure: "無法寫入匯出檔",
                informative: error.localizedDescription
            )
            return
        }

        let done = NSAlert()
        done.messageText = "已匯出使用者資料"
        done.informativeText =
            "包含 \(archive.characters.count) 筆選字紀錄與 \(archive.phrases.count) 個使用者詞。"
        done.addButton(withTitle: "好")
        done.runModal()
    }

    @objc private func importUserData(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let archive: UserDataArchive
        let issues: UserDataArchiveIssues
        do {
            (archive, issues) = try UserDataArchive.decoded(
                from: try Data(contentsOf: url)
            )
        } catch {
            report(
                failure: "無法匯入這個檔案",
                informative: error.localizedDescription
            )
            return
        }

        guard let summary = learning.merge(archive) else {
            report(
                failure: "無法匯入使用者資料",
                informative: "資料庫目前無法寫入，既有資料仍然保留。"
            )
            return
        }

        reloadLists()

        var informative =
            "合併了 \(summary.mergedCharacters) 筆選字紀錄與 \(summary.mergedPhrases) 個使用者詞。"
        if !issues.isEmpty {
            informative +=
                "\n略過 \(issues.skippedCharacters) 筆無法辨識的選字紀錄與 \(issues.skippedPhrases) 個無法辨識的詞。"
        }
        let done = NSAlert()
        done.messageText = "已匯入使用者資料"
        done.informativeText = informative
        done.addButton(withTitle: "好")
        done.runModal()
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

        let cleared = operation()
        reloadLists()
        guard cleared else {
            report(
                failure: "無法清除使用者資料",
                informative: "資料庫目前無法寫入，既有資料仍然保留。"
            )
            return
        }
    }

    private func report(failure message: String, informative: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func reloadCloudSyncStatus() {
        cloudSyncStatusLabel?.stringValue =
            learning.cloudSyncStatus.localizedDescription
    }

    private static func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "JiukongZhuyin-UserData-\(formatter.string(from: Date())).json"
    }
}
