import XCTest

final class SecureSystemUIFocusTests: XCTestCase {
    private final class Controller {}

    private let delay = SecureSystemUI.releaseDelay
    private let appStore = "com.apple.AppStore"
    private let paymentView = "com.apple.AMSUIPaymentViewService"
    private let storeKitService = "com.apple.StoreKit.UIService"
    private let passKit = "com.apple.PassKit.PaymentAuthorizationUIExtension"

    func testOrdinaryClientsNeverHideTheOverlays() {
        var focus = SecureSystemUIFocus<Controller>()
        let editor = Controller()
        let finder = Controller()

        focus.activated(editor, clientBundleIdentifier: "com.apple.TextEdit", at: 0)
        focus.activated(finder, clientBundleIdentifier: "com.apple.finder", at: 1)
        focus.deactivated(finder, at: 2)
        focus.receivedEvent(from: editor, at: 3)
        focus.activated(Controller(), clientBundleIdentifier: nil, at: 4)

        XCTAssertFalse(focus.hidesOverlays)
        XCTAssertNil(focus.releaseTime)
    }

    func testEveryListedScreenHidesTheOverlaysAsSoonAsItHasFocus() {
        for identifier in SecureSystemUI.clientBundleIdentifiers {
            var focus = SecureSystemUIFocus<Controller>()
            focus.activated(Controller(), clientBundleIdentifier: appStore, at: 0)
            focus.activated(Controller(), clientBundleIdentifier: identifier, at: 1)
            XCTAssertTrue(focus.hidesOverlays, identifier)
            XCTAssertNil(focus.releaseTime, identifier)
        }
    }

    func testOnlyExactIdentifiersCount() {
        XCTAssertFalse(SecureSystemUI.isSecure(clientBundleIdentifier: nil))
        XCTAssertFalse(SecureSystemUI.isSecure(clientBundleIdentifier: "com.apple.AppStore"))
        XCTAssertFalse(SecureSystemUI.isSecure(clientBundleIdentifier: "com.apple.PassKit"))
        XCTAssertFalse(
            SecureSystemUI.isSecure(clientBundleIdentifier: passKit.uppercased())
        )
        XCTAssertTrue(SecureSystemUI.isSecure(clientBundleIdentifier: passKit))
    }

    func testAppStorePurchaseKeepsOverlaysHiddenAcrossTheHandOff() {
        // Traced on 2026-10-21: the payment view service deactivated 18 ms
        // before the payment extension activated, and the App Store's own
        // controller, never deactivated, was current in between.
        var focus = SecureSystemUIFocus<Controller>()
        let store = Controller()
        let view = Controller()
        let sheet = Controller()

        focus.activated(store, clientBundleIdentifier: appStore, at: 10)
        focus.activated(view, clientBundleIdentifier: paymentView, at: 17.515)
        XCTAssertTrue(focus.hidesOverlays)

        focus.deactivated(view, at: 18.785)
        XCTAssertTrue(focus.hidesOverlays)
        XCTAssertEqual(focus.releaseTime, 18.785 + delay)

        focus.activated(sheet, clientBundleIdentifier: passKit, at: 18.803)
        XCTAssertTrue(focus.hidesOverlays)
        XCTAssertNil(focus.releaseTime)

        // The release that was pending must not show the overlays now.
        focus.refresh(at: 18.785 + delay)
        XCTAssertTrue(focus.hidesOverlays)
    }

    func testInAppPurchaseOverlapsKeepOverlaysHidden() {
        // The StoreKit service activated again before the payment extension
        // deactivated, then the sheet was cancelled.
        var focus = SecureSystemUIFocus<Controller>()
        let host = Controller()
        let service = Controller()
        let sheet = Controller()

        focus.activated(host, clientBundleIdentifier: "tw.idv.jiukong.status", at: 0)
        focus.activated(service, clientBundleIdentifier: storeKitService, at: 1)
        focus.activated(sheet, clientBundleIdentifier: passKit, at: 1.6)
        focus.deactivated(service, at: 1.8)
        focus.activated(service, clientBundleIdentifier: storeKitService, at: 4.5)
        focus.deactivated(sheet, at: 4.75)
        XCTAssertTrue(focus.hidesOverlays)
        XCTAssertNil(focus.releaseTime)

        focus.deactivated(service, at: 5.3)
        XCTAssertTrue(focus.hidesOverlays)
        focus.refresh(at: 5.3 + delay)
        XCTAssertFalse(focus.hidesOverlays)
    }

    func testOverlaysReturnOnlyAfterTheReleaseDelay() {
        var focus = SecureSystemUIFocus<Controller>()
        let store = Controller()
        let sheet = Controller()
        focus.activated(store, clientBundleIdentifier: appStore, at: 0)
        focus.activated(sheet, clientBundleIdentifier: passKit, at: 1)

        focus.deactivated(sheet, at: 20)
        XCTAssertTrue(focus.hidesOverlays)
        XCTAssertEqual(focus.releaseTime, 20 + delay)

        // Later events neither push the release back nor bring it forward.
        focus.receivedEvent(from: store, at: 20.2)
        XCTAssertEqual(focus.releaseTime, 20 + delay)
        focus.refresh(at: 20 + delay - 0.01)
        XCTAssertTrue(focus.hidesOverlays)

        focus.refresh(at: 20 + delay)
        XCTAssertFalse(focus.hidesOverlays)
        XCTAssertNil(focus.releaseTime)
    }

    func testFocusReturningToTheSheetCancelsThePendingRelease() {
        var focus = SecureSystemUIFocus<Controller>()
        let editor = Controller()
        let sheet = Controller()
        focus.activated(sheet, clientBundleIdentifier: passKit, at: 0)
        focus.activated(editor, clientBundleIdentifier: "com.microsoft.VSCode", at: 5)
        XCTAssertNotNil(focus.releaseTime)

        // Clicking the still-open sheet makes it current again.
        focus.receivedEvent(from: sheet, at: 5.2)
        XCTAssertTrue(focus.hidesOverlays)
        XCTAssertNil(focus.releaseTime)
        focus.refresh(at: 5 + delay)
        XCTAssertTrue(focus.hidesOverlays)
    }

    func testAnOrdinaryClientReceivingEventsEndsHidingWithoutADeactivation() {
        // A sheet's deactivation that never arrives must not hide the
        // indicator for good: the app the user types into takes over.
        var focus = SecureSystemUIFocus<Controller>()
        let editor = Controller()
        let sheet = Controller()
        focus.activated(editor, clientBundleIdentifier: "com.apple.TextEdit", at: 0)
        focus.activated(sheet, clientBundleIdentifier: passKit, at: 1)

        focus.receivedEvent(from: editor, at: 30)
        XCTAssertTrue(focus.hidesOverlays)
        focus.refresh(at: 30 + delay)
        XCTAssertFalse(focus.hidesOverlays)
    }

    func testDeactivatingAStaleClientResumesTheSheet() {
        // Like LINE and Finder after Cmd-Tab, an older client can activate
        // and deactivate again after the sheet already has focus.
        var focus = SecureSystemUIFocus<Controller>()
        let finder = Controller()
        let sheet = Controller()
        focus.activated(finder, clientBundleIdentifier: "com.apple.finder", at: 0)
        focus.activated(sheet, clientBundleIdentifier: passKit, at: 1)
        focus.activated(finder, clientBundleIdentifier: "com.apple.finder", at: 1.01)
        focus.deactivated(finder, at: 1.02)

        XCTAssertTrue(focus.hidesOverlays)
        XCTAssertNil(focus.releaseTime)
    }

    func testAClosedSheetControllerNoLongerCounts() {
        var focus = SecureSystemUIFocus<Controller>()
        let editor = Controller()
        var sheet: Controller? = Controller()
        focus.activated(editor, clientBundleIdentifier: "com.apple.TextEdit", at: 0)
        focus.activated(sheet!, clientBundleIdentifier: passKit, at: 1)
        sheet = nil

        focus.refresh(at: 2)
        XCTAssertTrue(focus.hidesOverlays)
        focus.refresh(at: 2 + delay)
        XCTAssertFalse(focus.hidesOverlays)
    }
}
