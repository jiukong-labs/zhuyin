import AppKit
import QuartzCore

private final class CursorIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A persistent, cursor-following indicator for the current language mode.
///
/// This answers "what mode am I in right now" without the user having to type
/// anything, including immediately after a Shift toggle. Only one exists per
/// process.
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
    private var hasActiveComposition = false
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
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

    /// Updated by the active input controller whenever its engine state
    /// changes. This never inspects marked text supplied by the client app.
    func updateCompositionActive(_ active: Bool) {
        precondition(Thread.isMainThread)
        guard hasActiveComposition != active else {
            return
        }
        hasActiveComposition = active
        refreshContent()
        resizePanel()
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
        if !active {
            hasActiveComposition = false
            refreshContent()
            resizePanel()
        }
        updateRunState()
    }

    private var isRunning: Bool {
        settings.isEnabled && isActive
    }

    private var currentPanelSize: NSSize {
        let style = settings.textSize.style
        return style.panelSize(
            showsCompositionIndicator: showsCompositionDot,
            capsLockSize: showsCapsLockBadge
                ? settings.capsLockIndicatorSize
                : nil
        )
    }

    private var showsCompositionDot: Bool {
        isRunning
            && mode == .chinese
            && hasActiveComposition
            && settings.showsCompositionIndicator
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
            showsComposition: showsCompositionDot,
            compositionColor: settings.appearance.compositionIndicatorColor,
            animatesComposition: CompositionIndicatorAnimationPolicy
                .shouldAnimate(
                    preferenceEnabled: settings.animatesCompositionIndicator,
                    reduceMotionEnabled: NSWorkspace.shared
                        .accessibilityDisplayShouldReduceMotion
                ),
            showsCapsLock: showsCapsLockBadge
        )
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        refreshContent()
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

final class CursorIndicatorContentView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let compositionDotView = NSView()
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
        compositionDotView.wantsLayer = true
        compositionDotView.isHidden = true
        capsLockLabel.alignment = .left
        capsLockLabel.textColor = CursorIndicatorAppearance.capsLockColor
        capsLockLabel.isHidden = true

        addSubview(label)
        addSubview(compositionDotView)
        addSubview(capsLockLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
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

    func update(
        text: String,
        color: NSColor,
        showsComposition: Bool,
        compositionColor: NSColor,
        animatesComposition: Bool,
        showsCapsLock: Bool
    ) {
        label.stringValue = text
        label.textColor = color
        compositionDotView.isHidden = !showsComposition
        compositionDotView.layer?.backgroundColor = compositionColor.cgColor
        updateCompositionAnimation(
            showsComposition && animatesComposition
        )
        capsLockLabel.isHidden = !showsCapsLock
        setAccessibilityLabel(
            showsComposition ? "\(text)輸入模式，正在組字" : "\(text)輸入模式"
        )
        needsLayout = true
    }

    var isCompositionDotVisible: Bool {
        !compositionDotView.isHidden
    }

    var isCompositionDotAnimating: Bool {
        compositionDotView.layer?.animation(
            forKey: Self.compositionAnimationKey
        ) != nil
    }

    var compositionDotFrame: NSRect {
        compositionDotView.frame
    }

    var compositionDotColorHex: String? {
        guard let color = compositionDotView.layer?.backgroundColor,
              let appKitColor = NSColor(cgColor: color) else {
            return nil
        }
        return CursorIndicatorAppearance.hex(from: appKitColor)
    }

    var capsLockFrame: NSRect {
        capsLockLabel.frame
    }

    private static let compositionAnimationKey = "compositionBreathing"

    private func updateCompositionAnimation(_ animates: Bool) {
        guard let layer = compositionDotView.layer else {
            return
        }
        layer.removeAnimation(forKey: Self.compositionAnimationKey)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        guard animates else {
            return
        }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.35
        opacity.toValue = 1.0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.8
        scale.toValue = 1.0

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 1.35
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: Self.compositionAnimationKey)
    }

    // Laid out by hand because the panel is resized from outside whenever the
    // Caps Lock badge appears, and a constraint pass would fight that.
    override func layout() {
        super.layout()

        let labelWidth = min(style.panelSize.width, bounds.width)

        label.frame = NSRect(
            x: 0,
            y: 0,
            width: labelWidth,
            height: bounds.height
        )
        var nextX = labelWidth
        if !compositionDotView.isHidden {
            nextX += style.compositionDotGap
            let diameter = style.compositionDotDiameter
            compositionDotView.frame = NSRect(
                x: nextX,
                y: (bounds.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            compositionDotView.layer?.cornerRadius = diameter / 2
            nextX += diameter
        } else {
            compositionDotView.frame = .zero
        }

        let badgeWidth = style.capsLockBadgeWidth(for: capsLockSize)
        let gap = style.capsLockBadgeGap(for: capsLockSize)
        if !capsLockLabel.isHidden {
            nextX += gap
        }
        capsLockLabel.frame = NSRect(
            x: nextX,
            y: 0,
            width: capsLockLabel.isHidden ? 0 : badgeWidth,
            height: bounds.height
        )
    }
}
