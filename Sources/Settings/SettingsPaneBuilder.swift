import AppKit

/// Shared layout for the settings tabs, so every pane has the same rhythm of
/// bold title, controls, separator, and secondary explanatory note.
enum SettingsPaneBuilder {
    static let contentWidth: CGFloat = 440

    static func pane(sections: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, section) in sections.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(separator())
            }
            stack.addArrangedSubview(section)
        }

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

    static func section(
        title: String,
        controls: [NSView],
        note: String
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let noteLabel = NSTextField(wrappingLabelWithString: note)
        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.preferredMaxLayoutWidth = contentWidth

        let stack = NSStackView(views: [titleLabel] + controls + [noteLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    static func separator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return separator
    }
}
