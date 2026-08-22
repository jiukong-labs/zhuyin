import AppKit

private final class LanguageModeHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A short-lived, nonactivating indicator for the current language mode.
final class LanguageModeHUD {
    static let shared = LanguageModeHUD()

    private static let displayDuration: TimeInterval = 0.75

    private let panel: LanguageModeHUDPanel
    private let label: NSTextField
    private var hideWorkItem: DispatchWorkItem?
    private var presentedToken: UUID?

    private init() {
        precondition(Thread.isMainThread)
        let initialSize = CursorIndicatorTextSize.small.style.panelSize
        panel = LanguageModeHUDPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        label = NSTextField(labelWithString: "")

        let background = NSVisualEffectView(
            frame: NSRect(origin: .zero, size: initialSize)
        )
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        label.frame = background.bounds
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 8, weight: .semibold)
        label.textColor = .labelColor
        label.autoresizingMask = [.width, .height]
        background.addSubview(label)

        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
    }

    @discardableResult
    func show(
        mode: LanguageMode,
        indicator: CursorIndicatorPreferences,
        clientWindowLevel: CGWindowLevel
    ) -> UUID {
        precondition(Thread.isMainThread)
        hideWorkItem?.cancel()
        let token = UUID()
        presentedToken = token

        let style = indicator.textSize.style
        label.stringValue = indicator.appearance.text(for: mode)
        label.textColor = indicator.appearance.color(for: mode)
        label.font = .monospacedSystemFont(
            ofSize: style.fontSize,
            weight: .semibold
        )
        label.setAccessibilityLabel(
            mode == .chinese ? "中文輸入模式" : "英文輸入模式"
        )
        panel.level = NSWindow.Level(rawValue: Int(clientWindowLevel) + 2)
        panel.setContentSize(style.panelSize)
        panel.setFrame(
            CursorIndicatorGeometry.frame(
                placement: indicator.placement,
                mouseLocation: NSEvent.mouseLocation,
                panelSize: style.panelSize,
                visibleFrames: NSScreen.screens.map(\.visibleFrame)
            ),
            display: true
        )
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.presentedToken == token else {
                return
            }
            self.presentedToken = nil
            self.panel.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.displayDuration,
            execute: workItem
        )
        return token
    }

    func hide(token: UUID) {
        precondition(Thread.isMainThread)
        guard presentedToken == token else {
            return
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        presentedToken = nil
        panel.orderOut(nil)
    }
}
