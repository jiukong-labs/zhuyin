import AppKit

/// The settings pane for the cursor-following mode indicator.
///
/// Every control writes straight through to `PreferencesController`, and the
/// pane re-reads that value when the window opens, so the stored preferences
/// are the only source of truth.
final class CursorIndicatorSettingsController: NSObject, NSTextFieldDelegate {
    private let preferences: PreferencesController

    private let enabledButton = NSButton(
        checkboxWithTitle: "在游標旁顯示目前輸入模式",
        target: nil,
        action: nil
    )
    private let placementButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let trackingButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textSizeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let compositionIndicatorButton = NSButton(
        checkboxWithTitle: "組字時顯示狀態圓點",
        target: nil,
        action: nil
    )
    private let compositionAnimationButton = NSButton(
        checkboxWithTitle: "使用呼吸動畫",
        target: nil,
        action: nil
    )
    private let capsLockButton = NSButton(
        checkboxWithTitle: "Caps Lock 開啟時一併顯示 ⇪",
        target: nil,
        action: nil
    )
    private let capsLockSizeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let chineseTextField = NSTextField(string: "")
    private let englishTextField = NSTextField(string: "")
    private let chineseColorWell = NSColorWell()
    private let englishColorWell = NSColorWell()
    private let compositionColorWell = NSColorWell()

    private static let placements = CursorIndicatorPlacement.allCases
    private static let trackings = CursorIndicatorTracking.allCases
    private static let textSizes = CursorIndicatorTextSize.allCases
    private static let capsLockSizes = CapsLockIndicatorSize.allCases

    init(preferences: PreferencesController = .shared) {
        self.preferences = preferences
        super.init()
    }

    func makeView() -> NSView {
        enabledButton.target = self
        enabledButton.action = #selector(enabledDidChange(_:))
        capsLockButton.target = self
        capsLockButton.action = #selector(capsLockDidChange(_:))
        compositionIndicatorButton.target = self
        compositionIndicatorButton.action = #selector(
            compositionIndicatorDidChange(_:)
        )
        compositionAnimationButton.target = self
        compositionAnimationButton.action = #selector(
            compositionAnimationDidChange(_:)
        )

        configure(
            placementButton,
            titles: Self.placements.map(\.localizedName),
            action: #selector(placementDidChange(_:))
        )
        configure(
            trackingButton,
            titles: Self.trackings.map(\.localizedName),
            action: #selector(trackingDidChange(_:))
        )
        configure(
            textSizeButton,
            titles: Self.textSizes.map(\.localizedName),
            action: #selector(textSizeDidChange(_:))
        )
        configure(
            capsLockSizeButton,
            titles: Self.capsLockSizes.map(\.localizedName),
            action: #selector(capsLockSizeDidChange(_:))
        )

        for field in [chineseTextField, englishTextField] {
            field.delegate = self
            field.placeholderString = "預設"
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        }
        chineseColorWell.target = self
        chineseColorWell.action = #selector(chineseColorDidChange(_:))
        englishColorWell.target = self
        englishColorWell.action = #selector(englishColorDidChange(_:))
        compositionColorWell.target = self
        compositionColorWell.action = #selector(compositionColorDidChange(_:))
        for well in [
            chineseColorWell,
            englishColorWell,
            compositionColorWell,
        ] {
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }

        let appearanceGrid = NSGridView(views: [
            [
                NSTextField(labelWithString: "中文"),
                chineseTextField,
                chineseColorWell,
                makeButton("重設", action: #selector(resetChinese(_:))),
            ],
            [
                NSTextField(labelWithString: "英文"),
                englishTextField,
                englishColorWell,
                makeButton("重設", action: #selector(resetEnglish(_:))),
            ],
            [
                NSTextField(labelWithString: "組字狀態"),
                NSTextField(labelWithString: ""),
                compositionColorWell,
                makeButton("重設", action: #selector(resetCompositionColor(_:))),
            ],
        ])
        appearanceGrid.rowSpacing = 8
        appearanceGrid.columnSpacing = 10

        let capsLockRow = NSStackView(views: [
            capsLockButton,
            NSTextField(labelWithString: "大小"),
            capsLockSizeButton,
        ])
        capsLockRow.orientation = .horizontal
        capsLockRow.spacing = 10

        let positionRow = NSStackView(views: [
            NSTextField(labelWithString: "位置"),
            placementButton,
            NSTextField(labelWithString: "追蹤"),
            trackingButton,
            NSTextField(labelWithString: "大小"),
            textSizeButton,
        ])
        positionRow.orientation = .horizontal
        positionRow.spacing = 8

        return SettingsPaneBuilder.pane(sections: [
            SettingsPaneBuilder.section(
                title: "游標指示器",
                controls: [enabledButton, positionRow],
                note: "只在使用久空輸入法時顯示；切換到其他輸入法會自動消失。開啟後就不再顯示切換時的短暫提示，避免同時出現兩個指示。"
            ),
            SettingsPaneBuilder.section(
                title: "組字狀態",
                controls: [
                    compositionIndicatorButton,
                    compositionAnimationButton,
                ],
                note: "部分網頁編輯器不會顯示組字底線。開啟後，組字期間會在游標指示器旁顯示狀態圓點。"
            ),
            SettingsPaneBuilder.section(
                title: "Caps Lock",
                controls: [capsLockRow],
                note: "Caps Lock 狀態每 0.2 秒檢查一次，不需要輸入監控權限。"
            ),
            SettingsPaneBuilder.section(
                title: "文字與顏色",
                controls: [appearanceGrid],
                note: "留空即使用預設的「中」與「A」。文字最多 4 個字元。"
            ),
        ])
    }

    func reload() {
        let indicator = preferences.current.cursorIndicator

        enabledButton.state = indicator.isEnabled ? .on : .off
        compositionIndicatorButton.state = indicator.showsCompositionIndicator
            ? .on
            : .off
        compositionAnimationButton.state = indicator.animatesCompositionIndicator
            ? .on
            : .off
        compositionAnimationButton.isEnabled = indicator.showsCompositionIndicator
        capsLockButton.state = indicator.showsCapsLockIndicator ? .on : .off
        select(placementButton, index: Self.placements.firstIndex(of: indicator.placement))
        select(trackingButton, index: Self.trackings.firstIndex(of: indicator.tracking))
        select(textSizeButton, index: Self.textSizes.firstIndex(of: indicator.textSize))
        select(
            capsLockSizeButton,
            index: Self.capsLockSizes.firstIndex(of: indicator.capsLockIndicatorSize)
        )

        chineseTextField.stringValue = indicator.appearance.chineseText ?? ""
        englishTextField.stringValue = indicator.appearance.englishText ?? ""
        chineseColorWell.color = indicator.appearance.color(for: .chinese)
        englishColorWell.color = indicator.appearance.color(for: .english)
        compositionColorWell.color = indicator.appearance
            .compositionIndicatorColor
    }

    private func configure(
        _ button: NSPopUpButton,
        titles: [String],
        action: Selector
    ) {
        button.removeAllItems()
        for title in titles {
            button.addItem(withTitle: title)
        }
        button.target = self
        button.action = action
    }

    private func select(_ button: NSPopUpButton, index: Int?) {
        guard let index, button.numberOfItems > index else {
            return
        }
        button.selectItem(at: index)
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func update(_ transform: (inout CursorIndicatorPreferences) -> Void) {
        preferences.update { transform(&$0.cursorIndicator) }
    }

    @objc private func enabledDidChange(_ sender: NSButton) {
        update { $0.isEnabled = sender.state == .on }
    }

    @objc private func capsLockDidChange(_ sender: NSButton) {
        update { $0.showsCapsLockIndicator = sender.state == .on }
    }

    @objc private func compositionIndicatorDidChange(_ sender: NSButton) {
        update { $0.showsCompositionIndicator = sender.state == .on }
        compositionAnimationButton.isEnabled = sender.state == .on
    }

    @objc private func compositionAnimationDidChange(_ sender: NSButton) {
        update { $0.animatesCompositionIndicator = sender.state == .on }
    }

    @objc private func placementDidChange(_ sender: NSPopUpButton) {
        guard Self.placements.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        update { $0.placement = Self.placements[sender.indexOfSelectedItem] }
    }

    @objc private func trackingDidChange(_ sender: NSPopUpButton) {
        guard Self.trackings.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        update { $0.tracking = Self.trackings[sender.indexOfSelectedItem] }
    }

    @objc private func textSizeDidChange(_ sender: NSPopUpButton) {
        guard Self.textSizes.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        update { $0.textSize = Self.textSizes[sender.indexOfSelectedItem] }
    }

    @objc private func capsLockSizeDidChange(_ sender: NSPopUpButton) {
        guard Self.capsLockSizes.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        update {
            $0.capsLockIndicatorSize = Self.capsLockSizes[sender.indexOfSelectedItem]
        }
    }

    @objc private func chineseColorDidChange(_ sender: NSColorWell) {
        update {
            $0.appearance.chineseColorHex = CursorIndicatorAppearance
                .hex(from: sender.color)
        }
    }

    @objc private func englishColorDidChange(_ sender: NSColorWell) {
        update {
            $0.appearance.englishColorHex = CursorIndicatorAppearance
                .hex(from: sender.color)
        }
    }

    @objc private func compositionColorDidChange(_ sender: NSColorWell) {
        update {
            $0.appearance.compositionIndicatorColorHex =
                CursorIndicatorAppearance.hex(from: sender.color)
        }
    }

    @objc private func resetChinese(_ sender: Any?) {
        update {
            $0.appearance.chineseText = nil
            $0.appearance.chineseColorHex = nil
        }
        reload()
    }

    @objc private func resetEnglish(_ sender: Any?) {
        update {
            $0.appearance.englishText = nil
            $0.appearance.englishColorHex = nil
        }
        reload()
    }

    @objc private func resetCompositionColor(_ sender: Any?) {
        update { $0.appearance.compositionIndicatorColorHex = nil }
        reload()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }
        let text = CursorIndicatorAppearance.sanitizedText(field.stringValue)

        if field === chineseTextField {
            update { $0.appearance.chineseText = text }
        } else if field === englishTextField {
            update { $0.appearance.englishText = text }
        }
        field.stringValue = text ?? ""
    }
}
