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
//    Every run first proves the client is talking to Jiukong by requiring its
//    own candidate panel to appear, identified by window owner.
// 2. A running application keeps the input source it already adopted, so the
//    harness selects the source first and then launches a *new* client
//    instance, which adopts it at launch. The user's own TextEdit windows and
//    their input sources are never touched.
//
// Requires Accessibility and event-posting permission for the calling process,
// so it cannot run in continuous integration.

let inputMethodBundleID = "tw.idv.jiukong.inputmethod.zhuyin"
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
    let flags: CGEventFlags

    init(_ keyCode: Int, _ flags: CGEventFlags = []) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

func post(_ keystroke: Keystroke, to pid: pid_t) {
    for isDown in [true, false] {
        guard let event = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .privateState),
            virtualKey: CGKeyCode(keystroke.keyCode),
            keyDown: isDown
        ) else {
            continue
        }
        event.flags = keystroke.flags
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
}

let standardProbe = [kVK_ANSI_J, kVK_ANSI_I, kVK_ANSI_3]

let scripts: [String: AcceptanceScript] = [
    "single": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Return), Keystroke(kVK_Return),
        ],
        expectation: "我"
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
            Keystroke(kVK_Return), Keystroke(kVK_Return),
        ],
        expectation: "我，我"
    ),
    "brackets": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_LeftBracket),
            Keystroke(kVK_ANSI_J), Keystroke(kVK_ANSI_I), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_ANSI_RightBracket),
            Keystroke(kVK_ANSI_Backslash),
            Keystroke(kVK_Return),
        ],
        expectation: "「我」、"
    ),
    // Creates a user phrase, so it writes to the local learning database.
    "phrase": AcceptanceScript(
        probe: standardProbe,
        keystrokes: [
            Keystroke(kVK_ANSI_R), Keystroke(kVK_ANSI_U),
            Keystroke(kVK_ANSI_Period), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Space),
            Keystroke(kVK_ANSI_D), Keystroke(kVK_ANSI_J),
            Keystroke(kVK_ANSI_Slash), Keystroke(kVK_Space),
            Keystroke(kVK_Space),
            Keystroke(kVK_LeftArrow, .maskShift),
            Keystroke(kVK_LeftArrow, .maskShift),
            Keystroke(kVK_Return),
        ],
        expectation: "九空"
    ),
    // Requires JiukongKeyboardArrangement = eten before the process starts.
    "eten": AcceptanceScript(
        probe: [kVK_ANSI_X, kVK_ANSI_O, kVK_ANSI_3],
        keystrokes: [
            Keystroke(kVK_ANSI_X), Keystroke(kVK_ANSI_O), Keystroke(kVK_ANSI_3),
            Keystroke(kVK_Return), Keystroke(kVK_Return),
        ],
        expectation: "我"
    ),
    // Requires JiukongKeyboardArrangement = ibm before the process starts.
    "ibm": AcceptanceScript(
        probe: [kVK_ANSI_S, kVK_ANSI_G, kVK_ANSI_Comma],
        keystrokes: [
            Keystroke(kVK_ANSI_S), Keystroke(kVK_ANSI_G),
            Keystroke(kVK_ANSI_Comma),
            Keystroke(kVK_Return), Keystroke(kVK_Return),
        ],
        expectation: "我"
    ),
]

// MARK: - Run

let arguments = Array(CommandLine.arguments.dropFirst())
guard let scriptName = arguments.first, let script = scripts[scriptName] else {
    print("usage: JiukongAcceptanceHarness <script>")
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
    usleep(120_000)
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
