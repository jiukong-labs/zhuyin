import XCTest

final class ActiveControllerTrackerTests: XCTestCase {
    private final class Controller {}

    func testOverlappingHandOverKeepsTheNewController() {
        let old = Controller()
        let new = Controller()
        var tracker = ActiveControllerTracker<Controller>()

        tracker.activated(old)
        XCTAssertTrue(tracker.activated(new))
        XCTAssertFalse(tracker.deactivated(old))
        XCTAssertTrue(tracker.current === new)
    }

    func testLateReactivationOfThePreviousAppResumesTheFocusedController() {
        // Switching from LINE to VS Code: LINE activated and deactivated
        // twice more after VS Code activated, and VS Code never activated
        // again while its Shift taps kept arriving.
        let line = Controller()
        let code = Controller()
        var tracker = ActiveControllerTracker<Controller>()

        tracker.activated(line)
        tracker.deactivated(line)
        tracker.activated(code)
        tracker.activated(line)
        tracker.deactivated(line)
        tracker.activated(line)
        XCTAssertTrue(tracker.deactivated(line))

        XCTAssertTrue(tracker.current === code)
    }

    func testEventFromAnotherActivatedControllerTakesOver() {
        // Finder activated right after VS Code, which then received the keys.
        let code = Controller()
        let finder = Controller()
        var tracker = ActiveControllerTracker<Controller>()

        tracker.activated(code)
        tracker.activated(finder)
        XCTAssertTrue(tracker.receivedEvent(from: code))
        XCTAssertTrue(tracker.current === code)
        XCTAssertFalse(tracker.receivedEvent(from: code))

        tracker.deactivated(code)
        XCTAssertTrue(tracker.current === finder)
    }

    func testEventAdoptsAControllerWhenNoneIsCurrent() {
        let code = Controller()
        let line = Controller()
        var tracker = ActiveControllerTracker<Controller>()

        tracker.activated(line)
        tracker.deactivated(line)
        XCTAssertNil(tracker.current)

        XCTAssertTrue(tracker.receivedEvent(from: code))
        XCTAssertTrue(tracker.current === code)
    }

    func testDeactivatingTheLastControllerLeavesNoneCurrent() {
        let code = Controller()
        var tracker = ActiveControllerTracker<Controller>()

        tracker.activated(code)
        XCTAssertTrue(tracker.deactivated(code))
        XCTAssertNil(tracker.current)
    }

    func testReleasedControllerIsNotResumed() {
        let code = Controller()
        var tracker = ActiveControllerTracker<Controller>()
        var closed: Controller? = Controller()

        tracker.activated(closed!)
        tracker.activated(code)
        closed = nil
        tracker.deactivated(code)

        XCTAssertNil(tracker.current)
    }
}
