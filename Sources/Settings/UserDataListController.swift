import AppKit

/// A read-and-edit list over one of the learned data sets.
///
/// The rows are a snapshot: every edit re-reads the store, so a list can never
/// act on an entry that another window already deleted.
final class UserDataListController: NSObject,
                                    NSTableViewDataSource,
                                    NSTableViewDelegate {
    enum Kind {
        case characters
        case phrases
        case suppressedPhrases

        var textColumnTitle: String {
            switch self {
            case .characters:
                return "字"
            case .phrases, .suppressedPhrases:
                return "詞"
            }
        }

        var emptyMessage: String {
            switch self {
            case .characters:
                return "尚未學習任何選字。"
            case .phrases:
                return "尚未建立任何使用者詞。"
            case .suppressedPhrases:
                return "沒有已刪除的內建詞。"
            }
        }

        /// A removed built-in phrase has no usage count and cannot be pinned;
        /// it is one identity that stays hidden until the user restores it.
        var showsUsageColumns: Bool {
            switch self {
            case .characters, .phrases:
                return true
            case .suppressedPhrases:
                return false
            }
        }

        var primaryActionTitle: String {
            switch self {
            case .characters, .phrases:
                return "刪除…"
            case .suppressedPhrases:
                return "恢復…"
            }
        }
    }

    private enum ColumnID {
        static let text = NSUserInterfaceItemIdentifier("text")
        static let reading = NSUserInterfaceItemIdentifier("reading")
        static let count = NSUserInterfaceItemIdentifier("count")
        static let pinned = NSUserInterfaceItemIdentifier("pinned")
    }

    private let kind: Kind
    private let learning: UserLearningService
    private let isBuiltInPhrase: (String, [String]) -> Bool

    private var allRows: [UserDataListRow] = []
    private var visibleRows: [UserDataListRow] = []
    private var filterText = ""

    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton(title: "置頂", target: nil, action: nil)
    private let deleteButton = NSButton(title: "刪除…", target: nil, action: nil)
    private let customReadingButton = NSButton(
        title: "自訂讀音…",
        target: nil,
        action: nil
    )

    /// `isBuiltInPhrase` decides which removed phrases the current built-in
    /// dictionary still carries; only those are listed as removable-to-restore.
    init(
        kind: Kind,
        learning: UserLearningService = .shared,
        isBuiltInPhrase: @escaping (String, [String]) -> Bool = { _, _ in true }
    ) {
        self.kind = kind
        self.learning = learning
        self.isBuiltInPhrase = isBuiltInPhrase
        super.init()
    }

    func makeView() -> NSView {
        configureTableView()

        searchField.placeholderString = "搜尋"
        searchField.target = self
        searchField.action = #selector(searchFieldDidChange(_:))
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true

        pinButton.target = self
        pinButton.action = #selector(togglePin(_:))
        pinButton.isHidden = !kind.showsUsageColumns
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedRow(_:))
        deleteButton.title = kind.primaryActionTitle
        customReadingButton.target = self
        customReadingButton.action = #selector(showCustomReadings(_:))

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let buttonViews: [NSView]
        switch kind {
        case .characters:
            buttonViews = [pinButton, deleteButton, customReadingButton]
        case .phrases:
            buttonViews = [pinButton, deleteButton]
        case .suppressedPhrases:
            buttonViews = [deleteButton]
        }
        let buttonRow = NSStackView(views: buttonViews)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(
            views: [searchField, scrollView, buttonRow, statusLabel]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -32
            ),
            searchField.widthAnchor.constraint(equalToConstant: 220),
        ])
        return container
    }

    func reload() {
        switch kind {
        case .characters:
            allRows = learning.allCharacterRecords().map { record in
                UserDataListRow(
                    identity: .character(
                        text: record.character,
                        pronunciation: record.pronunciation
                    ),
                    text: record.character,
                    reading: record.pronunciation,
                    selectionCount: record.selectionCount,
                    pinned: record.pinned
                )
            }
        case .phrases:
            allRows = learning.allPhraseRecords().map { record in
                UserDataListRow(
                    identity: .phrase(
                        text: record.phrase,
                        readings: record.pronunciationSequence
                    ),
                    text: record.phrase,
                    reading: record.pronunciationSequence.joined(separator: " "),
                    selectionCount: record.selectionCount,
                    pinned: record.pinned
                )
            }
        case .suppressedPhrases:
            // A removal the dictionary itself has since dropped has nothing
            // left to restore, so it is not listed. The record is kept: other
            // devices may still run a dictionary that carries the phrase, and
            // a later dictionary could bring it back.
            allRows = learning.allSuppressedPhrases().filter {
                isBuiltInPhrase($0.phrase, $0.pronunciationSequence)
            }.map { record in
                UserDataListRow(
                    identity: .suppressedPhrase(
                        text: record.phrase,
                        readings: record.pronunciationSequence
                    ),
                    text: record.phrase,
                    reading: record.pronunciationSequence.joined(separator: " "),
                    selectionCount: 0,
                    pinned: false
                )
            }
        }
        applyFilter()
    }

    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.style = .inset

        var columns: [(
            NSUserInterfaceItemIdentifier,
            String,
            CGFloat,
            UserDataListSortColumn
        )] = [
            (ColumnID.text, kind.textColumnTitle, 90, .text),
            (ColumnID.reading, "注音", 170, .reading),
        ]
        if kind.showsUsageColumns {
            columns.append((ColumnID.count, "次數", 50, .count))
            columns.append((ColumnID.pinned, "置頂", 40, .pinned))
        }
        for (identifier, title, width, sortColumn) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: sortColumn.rawValue,
                ascending: sortColumn.initialAscending
            )
            tableView.addTableColumn(column)
        }
    }

    private func applyFilter() {
        let selectedIdentity = selectedRow()?.identity
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredRows = query.isEmpty
            ? allRows
            : allRows.filter {
                $0.searchText.localizedCaseInsensitiveContains(query)
            }
        visibleRows = UserDataListSorter.sorted(filteredRows, by: activeSort)
        tableView.reloadData()
        restoreSelection(for: selectedIdentity)
        updateStatus()
        updateButtons()
    }

    private var activeSort: UserDataListSort? {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let column = UserDataListSortColumn(rawValue: key) else {
            return nil
        }
        return UserDataListSort(
            column: column,
            ascending: descriptor.ascending
        )
    }

    private func restoreSelection(for identity: UserDataListRow.Identity?) {
        guard let identity,
              let index = visibleRows.firstIndex(where: {
                  $0.identity == identity
              }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(
            IndexSet(integer: index),
            byExtendingSelection: false
        )
    }

    private func updateStatus() {
        if allRows.isEmpty {
            statusLabel.stringValue = kind.emptyMessage
        } else if visibleRows.count == allRows.count {
            statusLabel.stringValue = "共 \(allRows.count) 筆。"
        } else {
            statusLabel.stringValue =
                "顯示 \(visibleRows.count) 筆，共 \(allRows.count) 筆。"
        }
    }

    private func updateButtons() {
        let row = selectedRow()
        pinButton.isEnabled = row != nil
        deleteButton.isEnabled = row != nil
        pinButton.title = (row?.pinned ?? false) ? "取消置頂" : "置頂"
    }

    private func selectedRow() -> UserDataListRow? {
        let index = tableView.selectedRow
        guard visibleRows.indices.contains(index) else {
            return nil
        }
        return visibleRows[index]
    }

    @objc private func searchFieldDidChange(_ sender: NSSearchField) {
        filterText = sender.stringValue
        applyFilter()
    }

    @objc private func togglePin(_ sender: Any?) {
        guard let row = selectedRow() else {
            return
        }

        switch row.identity {
        case let .character(text, pronunciation):
            learning.setPinned(
                !row.pinned,
                character: text,
                pronunciation: pronunciation
            )
        case let .phrase(text, readings):
            learning.setPhrasePinned(
                !row.pinned,
                phrase: text,
                pronunciationSequence: readings
            )
        case .suppressedPhrase:
            return
        }
        reload()
    }

    @objc private func showCustomReadings(_ sender: Any?) {
        CustomReadingSettingsController.shared.show()
    }

    @objc private func deleteSelectedRow(_ sender: Any?) {
        guard let row = selectedRow() else {
            return
        }

        let isRestore = kind == .suppressedPhrases
        let alert = NSAlert()
        alert.alertStyle = isRestore ? .informational : .warning
        alert.messageText = isRestore
            ? "恢復「\(row.text)」？"
            : "刪除「\(row.text)」？"
        alert.informativeText = isRestore
            ? "這個內建詞（\(row.reading)）會重新出現在候選視窗中。"
            : "會刪除這一筆（\(row.reading)）的使用次數與置頂狀態，此操作無法復原。"
        alert.addButton(withTitle: isRestore ? "恢復" : "刪除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let changed: Bool
        switch row.identity {
        case let .character(text, pronunciation):
            changed = learning.deleteCharacterRecord(
                character: text,
                pronunciation: pronunciation
            )
        case let .phrase(text, readings):
            changed = learning.deletePhrase(
                phrase: text,
                pronunciationSequence: readings
            )
        case let .suppressedPhrase(text, readings):
            changed = learning.restorePhrase(
                phrase: text,
                pronunciationSequence: readings
            )
        }

        if !changed {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = isRestore
                ? "無法恢復這個內建詞"
                : "無法刪除這一筆資料"
            failure.informativeText = "資料庫目前無法寫入，資料仍然保留。"
            failure.addButton(withTitle: "好")
            failure.runModal()
        }
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleRows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard visibleRows.indices.contains(row),
              let identifier = tableColumn?.identifier else {
            return nil
        }

        let entry = visibleRows[row]
        let value: String
        switch identifier {
        case ColumnID.text:
            value = entry.text
        case ColumnID.reading:
            value = entry.reading
        case ColumnID.count:
            value = String(entry.selectionCount)
        case ColumnID.pinned:
            value = entry.pinned ? "★" : ""
        default:
            return nil
        }

        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? NSTextField ?? {
                let field = NSTextField(labelWithString: "")
                field.identifier = identifier
                field.lineBreakMode = .byTruncatingTail
                return field
            }()
        cell.stringValue = value
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    func tableView(
        _ tableView: NSTableView,
        sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        applyFilter()
    }
}

/// Edits pronunciation aliases without touching the bundled dictionary. This
/// is a separate window so the existing settings tabs remain compact.
final class CustomReadingSettingsController: NSObject,
                                             NSWindowDelegate,
                                             NSTableViewDataSource,
                                             NSTableViewDelegate {
    static let shared = CustomReadingSettingsController()

    private enum ColumnID {
        static let character = NSUserInterfaceItemIdentifier("custom-character")
        static let reading = NSUserInterfaceItemIdentifier("custom-reading")
        static let builtIn = NSUserInterfaceItemIdentifier("built-in-readings")
    }

    private let service: any CustomReadingManaging
    private let dictionary: CharacterDictionary?
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let editButton = NSButton(title: "編輯…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "刪除…", target: nil, action: nil)

    private var rows: [CustomReadingRecord] = []
    private var window: NSWindow?

    init(
        service: any CustomReadingManaging = CustomReadingService.shared,
        dictionary: CharacterDictionary? = try? CharacterDictionary(bundle: .main)
    ) {
        self.service = service
        self.dictionary = dictionary
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(customReadingsDidChange(_:)),
            name: CustomReadingService.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        let window = existingOrNewWindow()
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "自訂讀音"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        window.center()
        self.window = window
        return window
    }

    private func makeContentView() -> NSView {
        configureTableView()

        let note = NSTextField(
            wrappingLabelWithString:
                "自訂讀音只會新增個人輸入別名，不會修改或刪除內建讀音。例如新增「播 → ㄅㄛ」後，ㄅㄛ與原本的ㄅㄛˋ都仍可輸入「播」。"
        )
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 500

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 250).isActive = true

        let addButton = NSButton(
            title: "新增…",
            target: self,
            action: #selector(addReading(_:))
        )
        editButton.target = self
        editButton.action = #selector(editReading(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteReading(_:))

        let buttons = NSStackView(views: [addButton, editButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [note, scrollView, buttons, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -32
            ),
        ])
        return container
    }

    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.style = .inset
        tableView.doubleAction = #selector(editReading(_:))
        tableView.target = self

        for (identifier, title, width) in [
            (ColumnID.character, "字", CGFloat(70)),
            (ColumnID.reading, "自訂讀音", CGFloat(150)),
            (ColumnID.builtIn, "內建讀音", CGFloat(240)),
        ] {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
    }

    private func reload(selecting identity: String? = nil) {
        rows = service.allCustomReadings()
        tableView.reloadData()
        if let identity,
           let index = rows.firstIndex(where: { Self.identity(for: $0) == identity }) {
            tableView.selectRowIndexes(
                IndexSet(integer: index),
                byExtendingSelection: false
            )
        } else if !rows.indices.contains(tableView.selectedRow) {
            tableView.deselectAll(nil)
        }
        statusLabel.stringValue = rows.isEmpty
            ? "尚未新增任何自訂讀音。"
            : "共 \(rows.count) 筆自訂讀音。"
        updateButtons()
    }

    private func selectedRecord() -> CustomReadingRecord? {
        let index = tableView.selectedRow
        guard rows.indices.contains(index) else {
            return nil
        }
        return rows[index]
    }

    private func updateButtons() {
        let hasSelection = selectedRecord() != nil
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }

    @objc private func addReading(_ sender: Any?) {
        presentEditor(existing: nil)
    }

    @objc private func editReading(_ sender: Any?) {
        guard let record = selectedRecord() else {
            return
        }
        presentEditor(existing: record)
    }

    @objc private func deleteReading(_ sender: Any?) {
        guard let record = selectedRecord() else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "刪除「\(record.character) → \(record.pronunciation)」？"
        alert.informativeText = "只會刪除這個自訂讀音；內建詞庫中的原有讀音不受影響。"
        alert.addButton(withTitle: "刪除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        guard service.deleteCustomReading(
            character: record.character,
            pronunciation: record.pronunciation
        ) else {
            showWriteFailure()
            return
        }
        reload()
    }

    private func presentEditor(existing: CustomReadingRecord?) {
        let characterField = NSTextField(string: existing?.character ?? "")
        let readingField = NSTextField(string: existing?.pronunciation ?? "")
        characterField.placeholderString = "例如：播"
        readingField.placeholderString = "例如：ㄅㄛ"
        characterField.translatesAutoresizingMaskIntoConstraints = false
        readingField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            characterField.widthAnchor.constraint(equalToConstant: 220),
            readingField.widthAnchor.constraint(equalToConstant: 220),
            characterField.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            readingField.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "字："), characterField],
            [NSTextField(labelWithString: "自訂讀音："), readingField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        // NSAlert does not reliably derive an accessory view's height from an
        // NSGridView on newer macOS releases. Give the alert a concrete host
        // view so the two text fields cannot collapse to horizontal lines.
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 64))
        form.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            grid.topAnchor.constraint(equalTo: form.topAnchor),
            grid.bottomAnchor.constraint(equalTo: form.bottomAnchor),
        ])

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = existing == nil ? "新增自訂讀音" : "編輯自訂讀音"
        alert.informativeText = "一聲不加聲調符號，例如 ㄅㄛ；二、三、四聲使用 ˊ、ˇ、ˋ。"
        alert.accessoryView = form
        alert.addButton(withTitle: existing == nil ? "新增" : "儲存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = characterField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        // Force AppKit's field editor to commit any marked/composing text before
        // reading stringValue. Without this, a click on the alert button can
        // leave the visible last composition only in the shared field editor.
        alert.window.makeFirstResponder(nil)
        characterField.validateEditing()
        readingField.validateEditing()

        let validated: ValidatedCustomReading
        do {
            validated = try CustomReadingValidator.validate(
                character: characterField.stringValue,
                pronunciation: readingField.stringValue
            )
        } catch {
            showValidationError(error.localizedDescription)
            return
        }

        if builtInContains(validated) {
            let duplicate = NSAlert()
            duplicate.alertStyle = .informational
            duplicate.messageText = "內建詞庫已有這個讀音"
            duplicate.informativeText =
                "「\(validated.character)」本來就能用 \(validated.pronunciation) 輸入，不需要再新增自訂讀音。"
            duplicate.addButton(withTitle: "好")
            duplicate.runModal()
            return
        }

        let changed: Bool
        if let existing {
            changed = service.replaceCustomReading(
                existing,
                character: validated.character,
                pronunciation: validated.pronunciation
            )
        } else {
            changed = service.upsertCustomReading(
                character: validated.character,
                pronunciation: validated.pronunciation
            )
        }
        guard changed else {
            showWriteFailure()
            return
        }
        reload(
            selecting: Self.identity(
                character: validated.character,
                pronunciation: validated.pronunciation
            )
        )
    }

    private func builtInContains(_ reading: ValidatedCustomReading) -> Bool {
        guard let dictionary,
              let readings = try? dictionary.pronunciations(
                  for: reading.character
              ) else {
            return false
        }
        return readings.contains(reading.pronunciation)
    }

    private func builtInReadings(for character: String) -> String {
        guard let dictionary,
              let readings = try? dictionary.pronunciations(for: character),
              !readings.isEmpty else {
            return "—"
        }
        return readings.joined(separator: "、")
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "無法儲存自訂讀音"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showWriteFailure() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "無法儲存自訂讀音"
        alert.informativeText = "個人讀音檔目前無法寫入，原有資料未變更。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func customReadingsDidChange(_ notification: Notification) {
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard rows.indices.contains(row),
              let identifier = tableColumn?.identifier else {
            return nil
        }
        let record = rows[row]
        let value: String
        switch identifier {
        case ColumnID.character:
            value = record.character
        case ColumnID.reading:
            value = record.pronunciation
        case ColumnID.builtIn:
            value = builtInReadings(for: record.character)
        default:
            return nil
        }

        let field = tableView.makeView(withIdentifier: identifier, owner: self)
            as? NSTextField ?? {
                let field = NSTextField(labelWithString: "")
                field.identifier = identifier
                field.lineBreakMode = .byTruncatingTail
                return field
            }()
        field.stringValue = value
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    private static func identity(for record: CustomReadingRecord) -> String {
        identity(
            character: record.character,
            pronunciation: record.pronunciation
        )
    }

    private static func identity(
        character: String,
        pronunciation: String
    ) -> String {
        pronunciation + "\u{1F}" + character
    }
}
