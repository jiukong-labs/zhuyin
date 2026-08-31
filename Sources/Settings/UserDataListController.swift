import AppKit

/// A read-and-edit list over one of the two learned data sets.
///
/// The rows are a snapshot: every edit re-reads the store, so a list can never
/// act on an entry that another window already deleted.
final class UserDataListController: NSObject,
                                    NSTableViewDataSource,
                                    NSTableViewDelegate {
    enum Kind {
        case characters
        case phrases

        var textColumnTitle: String {
            switch self {
            case .characters:
                return "字"
            case .phrases:
                return "詞"
            }
        }

        var emptyMessage: String {
            switch self {
            case .characters:
                return "尚未學習任何選字。"
            case .phrases:
                return "尚未建立任何使用者詞。"
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

    private var allRows: [UserDataListRow] = []
    private var visibleRows: [UserDataListRow] = []
    private var filterText = ""

    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton(title: "置頂", target: nil, action: nil)
    private let deleteButton = NSButton(title: "刪除…", target: nil, action: nil)

    init(kind: Kind, learning: UserLearningService = .shared) {
        self.kind = kind
        self.learning = learning
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
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedRow(_:))

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let buttonRow = NSStackView(views: [pinButton, deleteButton])
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

        let columns: [(
            NSUserInterfaceItemIdentifier,
            String,
            CGFloat,
            UserDataListSortColumn
        )] = [
            (ColumnID.text, kind.textColumnTitle, 90, .text),
            (ColumnID.reading, "注音", 170, .reading),
            (ColumnID.count, "次數", 50, .count),
            (ColumnID.pinned, "置頂", 40, .pinned),
        ]
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
        }
        reload()
    }

    @objc private func deleteSelectedRow(_ sender: Any?) {
        guard let row = selectedRow() else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "刪除「\(row.text)」？"
        alert.informativeText =
            "會刪除這一筆（\(row.reading)）的使用次數與置頂狀態，此操作無法復原。"
        alert.addButton(withTitle: "刪除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let deleted: Bool
        switch row.identity {
        case let .character(text, pronunciation):
            deleted = learning.deleteCharacterRecord(
                character: text,
                pronunciation: pronunciation
            )
        case let .phrase(text, readings):
            deleted = learning.deletePhrase(
                phrase: text,
                pronunciationSequence: readings
            )
        }

        if !deleted {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "無法刪除這一筆資料"
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
