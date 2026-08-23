import AppKit

private final class CursorIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A persistent, cursor-following indicator for the current language mode.
///
/// This is the counterpart of the transient `LanguageModeHUD`: the HUD answers
/// "what did that Shift press do", while this answers "what mode am I in right
/// now" without the user having to type anything. Only one exists per process.
/// Its visibility is driven by `SystemInputSourceObserver`, which is the
/// process-wide source of truth for whether Jiukong is the selected system
/// input source: the indicator shows whenever that is true, regardless of
/// whether a text field currently has focus, and disappears as soon as the
/// user switches to another input source.
final class CursorIndicatorController {
    static let shared = CursorIndicatorController()

    private let panel: CursorIndicatorPanel
    private let contentView: CursorIndicatorContentView

    private var settings = CursorIndicatorPreferences()
    private var mode: LanguageMode = .chinese
    private var isActive = false
    private var isCapsLockOn = false
    private var trackingTimer: Timer?
    private var capsLockTimer: Timer?

    private init() {
        precondition(Thread.isMainThread)
        let style = CursorIndicatorTextSize.small.style
        contentView = CursorIndicatorContentView(
            frame: NSRect(origin: .zero, size: style.panelSize)
        )
        panel = CursorIndicatorPanel(
            contentRect: NSRect(origin: .zero, size: style.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = contentView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        // Must come *after* `isFloatingPanel = true`: that setter has the
        // side effect of resetting the window's level to `.floating`, which
        // was silently undoing every level assigned before it here (measured
        // via a runtime probe — the level always read back as `.floating`
        // regardless of what was requested). `.screenSaver` is high enough to
        // sit above the system Input Source menu in the menu bar, which sits
        // above `.popUpMenu` itself.
        panel.level = NSWindow.Level(
            rawValue: NSWindow.Level.screenSaver.rawValue + 1000
        )
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.orderOut(nil)
    }

    /// True when the indicator is configured to appear at all, which lets the
    /// caller suppress the transient HUD instead of showing two indicators.
    var isEnabled: Bool {
        settings.isEnabled
    }

    func apply(_ settings: CursorIndicatorPreferences) {
        precondition(Thread.isMainThread)
        self.settings = settings
        contentView.apply(
            style: settings.textSize.style,
            capsLockSize: settings.capsLockIndicatorSize
        )
        refreshContent()
        resizePanel()
        updateRunState()
    }

    func update(mode: LanguageMode) {
        precondition(Thread.isMainThread)
        self.mode = mode
        refreshContent()
        guard isRunning else {
            return
        }
        reposition(easing: false)
    }

    /// Called when a client starts or stops using this input method.
    func setActive(_ active: Bool) {
        precondition(Thread.isMainThread)
        jiukongDebugLog(
            "setActive called active=\(active) currentIsActive=\(isActive) isEnabled=\(settings.isEnabled)"
        )
        guard isActive != active else {
            return
        }
        isActive = active
        updateRunState()
    }

    private var isRunning: Bool {
        settings.isEnabled && isActive
    }

    private var currentPanelSize: NSSize {
        let style = settings.textSize.style
        guard showsCapsLockBadge else {
            return style.panelSize
        }
        return style.panelSize(
            withCapsLockBadge: settings.capsLockIndicatorSize
        )
    }

    private var showsCapsLockBadge: Bool {
        isCapsLockOn && settings.showsCapsLockIndicator
    }

    private func updateRunState() {
        jiukongDebugLog(
            "updateRunState isRunning=\(isRunning) isEnabled=\(settings.isEnabled) isActive=\(isActive)"
        )
        guard isRunning else {
            stopTimers()
            panel.orderOut(nil)
            return
        }

        startTimers()
        reposition(easing: false)
        panel.orderFrontRegardless()
        jiukongDebugLog(
            "indicator windowNumber=\(panel.windowNumber) requestedLevel=\(panel.level.rawValue) isVisible=\(panel.isVisible) frame=\(panel.frame)"
        )
    }

    private func refreshContent() {
        contentView.update(
            text: settings.appearance.text(for: mode),
            color: settings.appearance.color(for: mode),
            showsCapsLock: showsCapsLockBadge
        )
    }

    private func resizePanel() {
        let size = currentPanelSize
        contentView.setFrameSize(size)
        panel.setContentSize(size)
    }

    private func startTimers() {
        if trackingTimer == nil {
            let timer = Timer(
                timeInterval: CursorIndicatorGeometry.trackingInterval,
                repeats: true
            ) { [weak self] _ in
                guard let self else {
                    return
                }
                self.reposition(easing: self.settings.tracking == .followCursor)
            }
            timer.tolerance = CursorIndicatorGeometry.trackingInterval * 0.3
            RunLoop.main.add(timer, forMode: .common)
            trackingTimer = timer
        }

        if capsLockTimer == nil {
            let timer = Timer(
                timeInterval: 0.2,
                repeats: true
            ) { [weak self] _ in
                self?.pollCapsLock()
            }
            timer.tolerance = 0.06
            RunLoop.main.add(timer, forMode: .common)
            capsLockTimer = timer
            pollCapsLock()
        }
    }

    private func stopTimers() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        capsLockTimer?.invalidate()
        capsLockTimer = nil
    }

    /// Caps Lock can be toggled while this process holds no key focus, so it is
    /// polled rather than derived from the events the controller receives.
    private func pollCapsLock() {
        let isOn = CGEventSource.flagsState(.combinedSessionState)
            .contains(.maskAlphaShift)
        guard isOn != isCapsLockOn else {
            return
        }

        isCapsLockOn = isOn
        refreshContent()
        resizePanel()
        reposition(easing: false)
    }

    private func reposition(easing: Bool) {
        guard isRunning else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let panelSize = currentPanelSize
        let target = CursorIndicatorGeometry.frame(
            placement: settings.placement,
            mouseLocation: mouseLocation,
            panelSize: panelSize,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )

        let origin: NSPoint
        if easing, panel.isVisible {
            origin = CursorIndicatorGeometry.easedOrigin(
                from: panel.frame.origin,
                toward: target.origin
            )
        } else {
            origin = target.origin
        }

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }
}

private final class CursorIndicatorContentView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let capsLockLabel = NSTextField(
        labelWithString: CursorIndicatorAppearance.capsLockIndicator
    )

    private var style = CursorIndicatorTextSize.small.style
    private var capsLockSize = CapsLockIndicatorSize.extraLarge

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.alignment = .center
        capsLockLabel.alignment = .left
        capsLockLabel.textColor = CursorIndicatorAppearance.capsLockColor
        capsLockLabel.isHidden = true

        addSubview(label)
        addSubview(capsLockLabel)
        apply(style: style, capsLockSize: capsLockSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(style: CursorIndicatorStyle, capsLockSize: CapsLockIndicatorSize) {
        self.style = style
        self.capsLockSize = capsLockSize
        label.font = .monospacedSystemFont(ofSize: style.fontSize, weight: .semibold)
        capsLockLabel.font = .monospacedSystemFont(
            ofSize: style.capsLockFontSize(for: capsLockSize),
            weight: .bold
        )
        needsLayout = true
    }

    func update(text: String, color: NSColor, showsCapsLock: Bool) {
        label.stringValue = text
        label.textColor = color
        capsLockLabel.isHidden = !showsCapsLock
        needsLayout = true
    }

    // Laid out by hand because the panel is resized from outside whenever the
    // Caps Lock badge appears, and a constraint pass would fight that.
    override func layout() {
        super.layout()

        let badgeWidth = style.capsLockBadgeWidth(for: capsLockSize)
        let gap = style.capsLockBadgeGap(for: capsLockSize)
        let reservedWidth = capsLockLabel.isHidden ? 0 : gap + badgeWidth
        let labelWidth = max(0, bounds.width - reservedWidth)

        label.frame = NSRect(
            x: 0,
            y: 0,
            width: labelWidth,
            height: bounds.height
        )
        capsLockLabel.frame = NSRect(
            x: labelWidth + gap,
            y: 0,
            width: badgeWidth,
            height: bounds.height
        )
    }
}
