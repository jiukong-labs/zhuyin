import AppKit
import ApplicationServices
import Carbon

// Drives the *installed* input method through real CGEvent delivery to an
// isolated TextEdit document, then restores the previous input source.
//
// Two rules exist because breaking either produces confident nonsense:
//
// 1. The system's own Zhuyin input method composes the same Bopomofo from the
//    same keys. A run that never reached Jiukong therefore looks like a pass.
//    Every run first presses Down after a probe syllable and proves the client
//    is talking to Jiukong by requiring its candidate panel to appear.
// 2. A running application keeps the input source it already adopted, so the
//    harness selects the source first and then launches a *new* client
//    instance, which adopts it at launch. The user's own TextEdit windows and
//    their input sources are never touched.
//
// Requires Accessibility and event-posting permission for the calling process,
// so it cannot run in continuous integration.

let inputMethodBundleID = "tw.idv.jiukong.inputmethod.zhuyin.Chinese"
let clientApplicationURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

// MARK: - Input sources

func inputSource(id: String) -> TISInputSource? {
    let sources = TISCreateInputSourceList(nil, true)!
        .takeRetainedValue() as! [TISInputSource]
    return sources.first { identifier(of: $0) == id }
}

func identifier(of source: TISInputSource) -> String? {
    guard let raw = TISGetInputSourceProperty(
        source,
        kTISPropertyInputSourceID
    ) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func currentInputSourceID() -> String {
    identifier(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue()) ?? "?"
}

@discardableResult
func select(id: String) -> Bool {
    guard let source = inputSource(id: id) else {
        return false
    }
    return TISSelectInputSource(source) == noErr
}

// MARK: - Events

struct Keystroke {
    let keyCode: Int
    let keyDownFlags: CGEventFlags
    let keyUpFlags: CGEventFlags
    let settleDelayMicroseconds: useconds_t

    init(
        _ keyCode: Int,
        _ flags: CGEventFlags = [],
        settleDelayMicroseconds: useconds_t = 120_000
    ) {
        self.keyCode = keyCode
        keyDownFlags = flags
        keyUpFlags = flags
        self.settleDelayMicroseconds = settleDelayMicroseconds
    }

    /// Modifier-only gestures need different flags on press and release so
    /// InputMethodKit receives a real standalone `flagsChanged` pair.
    static func modifierTap(
        _ keyCode: Int,
        flag: CGEventFlags
    ) -> Keystroke {
        Keystroke(
            keyCode,
            keyDownFlags: flag,
            keyUpFlags: [],
            settleDelayMicroseconds: 900_000
        )
    }

    private init(
        _ keyCode: Int,
        keyDownFlags: CGEventFlags,
        keyUpFlags: CGEventFlags,
        settleDelayMicroseconds: useconds_t
    ) {
        self.keyCode = keyCode
        self.keyDownFlags = keyDownFlags
        self.keyUpFlags = keyUpFlags
        self.settleDelayMicroseconds = settleDelayMicroseconds
    }
}

let eventSource = CGEventSource(stateID: .privateState)

func post(_ keystroke: Keystroke, to pid: pid_t) {
    for isDown in [true, false] {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(keystroke.keyCode),
            keyDown: isDown
        ) else {
            continue
        }
        event.flags = isDown
            ? keystroke.keyDownFlags
            : keystroke.keyUpFlags
        event.postToPid(pid)
        usleep(28_000)
    }
}

func focusedText(pid: pid_t) -> String {
    let application = AXUIElementCreateApplication(pid)
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(
        application,
        kAXFocusedUIElementAttribute as CFString,
        &focused
    ) == .success, let element = focused else {
        return "<no focused element>"
    }

    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(
        element as! AXUIElement,
        kAXValueAttribute as CFString,
        &value
    ) == .success, let text = value as? String else {
        return "<no value>"
    }
    return text
}

func inputMethodPanelIsVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard let owner = window[kCGWindowOwnerName as String] as? String else {
            return false
        }
        return owner.contains("久空") || owner.contains("Jiukong")
    }
}

// MARK: - Scripts

struct AcceptanceScript {
    /// Keys that must raise the candidate panel on the arrangement under test.
    let probe: [Int]
    let keystrokes: [Keystroke]
    let expectation: String
    let includedInDefaultRun: Bool

    init(
        probe: [Int],
        keystrokes: [Keystroke],
        expectation: String,
        includedInDefaultRun: Bool = true
    ) {
        self.probe = probe
        self.keystrokes = keystrokes
        self.expectation = expectation
        self.includedInDefaultRun = includedInDefaultRun
    }
}

let standardProbe = [kVK_ANSI_J, kVK_ANSI_I, kVK_ANSI_3]

let scripts: [String: AcceptanceScript] = [
    "single": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Return),
        ],
        expectation: "我"
    ),
    // Top-row 1 is both candidate slot one and standard-layout ㄅ. It becomes
    // an explicit candidate number only after Down opens the chooser.
    "number-one": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_DownArrow),
            Keystroke(kVK_ANSI_1), Keystroke(kVK_Return),
        ],
        expectation: "我"
    ),
    // The second syllable begins on top-row 1 (standard ㄅ). Inline preview
    // must accept 我 implicitly and route 1 into ㄅ because Down was not used.
    "continuous": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_ANSI_1), Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Return),
        ],
        expectation: "我不"
    ),
    // Option ASCII is synthesized by Jiukong in Chinese mode rather than
    // relying on the client application's keyboard-layout pass-through.
    "option-ascii": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_A, .maskAlternate),
            Keystroke(kVK_ANSI_Z, .maskAlternate),
            Keystroke(kVK_ANSI_A, [.maskAlternate, .maskShift]),
            Keystroke(kVK_ANSI_Z, [.maskAlternate, .maskShift]),
            Keystroke(kVK_ANSI_0, .maskAlternate),
            Keystroke(kVK_ANSI_9, .maskAlternate),
        ],
        expectation: "azAZ09"
    ),
    // An Option ASCII shortcut must accept the active candidate exactly once
    // before inserting its literal text into the client.
    "option-after-composition": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I),
            Keystroke(kVK_ANSI_3),
            Keystroke(kVK_ANSI_A, .maskAlternate),
            Keystroke(kVK_ANSI_1, .maskAlternate),
        ],
        expectation: "我a1"
    ),
    // A complete Chinese → English → Chinese round trip proves both the
    // standalone modifier gesture and direct English-mode event pass-through.
    // Use a digit because TextEdit can automatically capitalize the first
    // Latin letter according to the developer's own substitution settings.
    "shift-round-trip": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            .modifierTap(kVK_Shift, flag: .maskShift),
            Keystroke(kVK_ANSI_1),
            .modifierTap(kVK_RightShift, flag: .maskShift),
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I),
            Keystroke(kVK_ANSI_3), Keystroke(kVK_Return),
        ],
        expectation: "1我"
    ),
    // ㄘㄜˋ initially falls back to CNS source-order 冊. Completing ㄕˋ
    // must offer the first-party exact phrase and replace that suffix with 測試.
    "builtin-phrase": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_H), Keystroke(kVK_ANSI_K),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Return),
        ],
        expectation: "測試"
    ),
    // Every intermediate syllable may start with a provisional CNS-order
    // character. The final reading must prefer Jiukong's exact six-reading
    // sentence and replace the complete marked suffix in one operation.
    "sentence": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_H), Keystroke(kVK_ANSI_K),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_5), Keystroke(kVK_ANSI_J),
            Keystroke(kVK_ANSI_Slash), Keystroke(kVK_Space),
            Keystroke(kVK_ANSI_F), Keystroke(kVK_ANSI_U),
            Keystroke(kVK_ANSI_Slash), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_L),
            Keystroke(kVK_Space),
            Keystroke(kVK_ANSI_C), Keystroke(kVK_ANSI_Period),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Return),
        ],
        expectation: "測試中請稍後"
    ),
    // Revision is intentionally two-stage. Left/Right first position the caret,
    // Down opens candidates for the reading immediately before that caret,
    // arrows then move the candidate highlight, and Up or Escape returns to
    // windowless text positioning without moving the caret.
    "revision-arrows": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_H), Keystroke(kVK_ANSI_K),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Space),
            Keystroke(kVK_LeftArrow),
            Keystroke(kVK_DownArrow), Keystroke(kVK_RightArrow),
            Keystroke(kVK_UpArrow), Keystroke(kVK_RightArrow),
            Keystroke(kVK_DownArrow), Keystroke(kVK_LeftArrow),
            Keystroke(kVK_Escape), Keystroke(kVK_LeftArrow),
            Keystroke(kVK_Return),
        ],
        expectation: "測試"
    ),
    // With 試 focused, Backspace restores the preceding 測 reading ㄘㄜˋ and
    // removes its tone. Return commits the remaining raw ㄘㄜ before 試.
    "revision-backspace": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_H), Keystroke(kVK_ANSI_K),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Space),
            Keystroke(kVK_LeftArrow), Keystroke(kVK_Delete),
            Keystroke(kVK_Return),
        ],
        expectation: "ㄘㄜ試"
    ),
    // With 試 on the right of the caret, Forward Delete restores ㄕˋ and
    // removes its tone. Return commits the raw ㄕ after the unchanged 測.
    "revision-forward-delete": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_H), Keystroke(kVK_ANSI_K),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Space),
            Keystroke(kVK_LeftArrow),
            Keystroke(kVK_ForwardDelete), Keystroke(kVK_Return),
        ],
        expectation: "測ㄕ"
    ),
    "escape": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Escape), Keystroke(kVK_Escape),
        ],
        expectation: ""
    ),
    "punctuation": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_ANSI_Comma, .maskShift),
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Return),
        ],
        expectation: "我，我"
    ),
    // Left from the text end must stop immediately before punctuation instead
    // of skipping it and landing before the preceding reading. Backspace then
    // reopens 試, removes its tone, and preserves the question mark.
    "punctuation-caret": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_H), Keystroke(kVK_ANSI_K),
            Keystroke(kVK_ANSI_4),
            Keystroke(kVK_ANSI_G), Keystroke(kVK_ANSI_4),
            Keystroke(kVK_Space),
            Keystroke(kVK_ANSI_Slash, .maskShift),
            Keystroke(kVK_LeftArrow), Keystroke(kVK_Delete),
            Keystroke(kVK_Return),
        ],
        expectation: "測ㄕ？"
    ),
    "brackets": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_LeftBracket),
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_ANSI_RightBracket),
            Keystroke(kVK_ANSI_Backslash),
            Keystroke(kVK_ANSI_Backslash, .maskShift),
            Keystroke(kVK_Return),
        ],
        expectation: "「我」、／"
    ),
    // Positions the caret after the final reading, then selects the two
    // readings immediately to its left. Creating a user phrase writes to the
    // local learning database.
    "phrase": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_R), Keystroke(kVK_ANSI_U),
            Keystroke(kVK_ANSI_Period), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Space),
            Keystroke(kVK_ANSI_D), Keystroke(kVK_ANSI_J),
            Keystroke(kVK_ANSI_Slash), Keystroke(kVK_Space),
            Keystroke(kVK_Space),
            Keystroke(kVK_LeftArrow),
            Keystroke(kVK_RightArrow),
            Keystroke(kVK_LeftArrow, .maskShift),
            Keystroke(kVK_Return),
        ],
        expectation: "久空"
    ),
    // Locates the first reading, then extends right from that focus. This is
    // the mirror path of the Shift-Left phrase acceptance above.
    "phrase-right": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_R), Keystroke(kVK_ANSI_U),
            Keystroke(kVK_ANSI_Period), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Space),
            Keystroke(kVK_ANSI_D), Keystroke(kVK_ANSI_J),
            Keystroke(kVK_ANSI_Slash), Keystroke(kVK_Space),
            Keystroke(kVK_Space),
            Keystroke(kVK_LeftArrow), Keystroke(kVK_LeftArrow),
            Keystroke(kVK_RightArrow, .maskShift),
            Keystroke(kVK_Return),
        ],
        expectation: "久空"
    ),
    // Requires JiukongKeyboardArrangement = eten before the process starts.
    "eten": AcceptanceScript(
        probe: [kVK_ANSI_X, kVK_ANSI_O, kVK_ANSI_3],
        keystrokes: [
            Keystroke(kVK_ANSI_X), Keystroke(kVK_ANSI_O), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Return),
        ],
        expectation: "我",
        includedInDefaultRun: false
    ),
    // Requires JiukongKeyboardArrangement = ibm before the process starts.
    "ibm": AcceptanceScript(
        probe: [kVK_ANSI_S, kVK_ANSI_G, kVK_ANSI_Comma],
        keystrokes: [
            Keystroke(kVK_ANSI_S), Keystroke(kVK_ANSI_G),
            Keystroke(kVK_ANSI_Comma),
            Keystroke(kVK_Return),
        ],
        expectation: "我",
        includedInDefaultRun: false
    ),
]

// MARK: - Run

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--list-default"] {
    let names = scripts
        .filter(\.value.includedInDefaultRun)
        .map(\.key)
        .sorted()
    print(names.joined(separator: "\n"))
    exit(0)
}

guard let scriptName = arguments.first, let script = scripts[scriptName] else {
    print("usage: JiukongAcceptanceHarness <script>")
    print("       JiukongAcceptanceHarness --list-default")
    print("scripts: \(scripts.keys.sorted().joined(separator: ", "))")
    exit(2)
}

guard AXIsProcessTrusted() else {
    print("failed: the calling process needs Accessibility permission")
    exit(1)
}

let previousInputSourceID = currentInputSourceID()
var restored = false
func restoreInputSource() {
    guard !restored else { return }
    restored = true
    select(id: previousInputSourceID)
    usleep(400_000)
}
atexit { restoreInputSource() }

guard select(id: inputMethodBundleID) else {
    print("failed: could not select \(inputMethodBundleID)")
    exit(1)
}
usleep(900_000)

let documentURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("jiukong-acceptance-\(UUID().uuidString).txt")
FileManager.default.createFile(atPath: documentURL.path, contents: Data())

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.createsNewApplicationInstance = true

var clientPID: pid_t = 0
let launched = DispatchSemaphore(value: 0)
NSWorkspace.shared.open(
    [documentURL],
    withApplicationAt: clientApplicationURL,
    configuration: configuration
) { application, _ in
    clientPID = application?.processIdentifier ?? 0
    launched.signal()
}
_ = launched.wait(timeout: .now() + 25)
usleep(1_800_000)

guard clientPID != 0 else {
    print("failed: could not launch the client application")
    exit(1)
}
let client = NSRunningApplication(processIdentifier: clientPID)

func finish(_ message: String, code: Int32) -> Never {
    restoreInputSource()
    client?.forceTerminate()
    try? FileManager.default.removeItem(at: documentURL)
    print(message)
    exit(code)
}

var connected = false
for _ in 0 ..< 3 {
    for key in script.probe {
        post(Keystroke(key), to: clientPID)
        usleep(120_000)
    }
    post(Keystroke(kVK_DownArrow), to: clientPID)
    usleep(700_000)
    connected = inputMethodPanelIsVisible()
    post(Keystroke(kVK_Escape), to: clientPID)
    post(Keystroke(kVK_Escape), to: clientPID)
    usleep(400_000)
    if connected { break }
    client?.activate(options: [.activateIgnoringOtherApps])
    usleep(700_000)
}

guard connected else {
    finish(
        "aborted: this client never routed keys through the input method",
        code: 1
    )
}

// Start from an empty document so the result is unambiguous.
post(Keystroke(kVK_ANSI_A, .maskCommand), to: clientPID)
usleep(200_000)
post(Keystroke(kVK_Delete), to: clientPID)
usleep(400_000)

for keystroke in script.keystrokes {
    post(keystroke, to: clientPID)
    usleep(keystroke.settleDelayMicroseconds)
}
usleep(700_000)

let text = focusedText(pid: clientPID)
let passed = text == script.expectation
finish(
    """
    \(passed ? "pass" : "FAIL") \(scriptName)
      expected: \(script.expectation.debugDescription)
      actual:   \(text.debugDescription)
    """,
    code: passed ? 0 : 1
)
