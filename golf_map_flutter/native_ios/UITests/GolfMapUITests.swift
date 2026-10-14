import XCTest

/// Smoke tests for the flows the plan names: play, save, reopen, and restore a round, and trace, edit, save,
/// and play a course. Each test starts from an empty install.
@MainActor
final class GolfMapUITests: XCTestCase {
    private let course = "Brackenridge Golf Course"
    private let timeout: TimeInterval = 15

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Attaches what was on screen to every failure, so CI results show it.
    nonisolated override func record(_ issue: XCTIssue) {
        var issue = issue
        let png = MainActor.assumeIsolated { XCUIScreen.main.screenshot().pngRepresentation }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.lifetime = .keepAlways
        issue.add(attachment)
        super.record(issue)
    }

    // MARK: Rounds

    func testPlaySaveAndReopenRound() throws {
        var app = launch()
        startRound(app, at: course)

        let score = element(app, "Score")
        XCTAssertTrue(score.waitForExistence(timeout: timeout))
        let startingScore = count(score)
        increase(score)
        XCTAssertEqual(count(score), startingScore + 1)
        increase(element(app, "Putts"))
        XCTAssertEqual(count(element(app, "Putts")), 1)

        app.buttons["Next hole"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hole 2'")).firstMatch.waitForExistence(timeout: timeout))
        increase(element(app, "Score"))

        endRound(app, choice: "Save round")
        XCTAssertTrue(app.navigationBars["Round saved"].waitForExistence(timeout: timeout))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: timeout))

        app.terminate()
        app = launch(reset: false)
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS 'over 2 holes'", "\(course),")).firstMatch
        scrollTo(saved, in: app)
        XCTAssertTrue(saved.exists, "The saved round should be listed on Home")
        saved.tap()
        XCTAssertTrue(app.navigationBars[course].waitForExistence(timeout: timeout))

        app.buttons["Continue editing"].tap()
        let reopened = element(app, "Score")
        XCTAssertTrue(reopened.waitForExistence(timeout: timeout))
        XCTAssertEqual(count(reopened), startingScore + 1)
        XCTAssertFalse(reopened.isEnabled, "Saving locks every hole, so the reopened hole's score is locked")
    }

    func testInterruptedRoundRestoresAtLaunch() throws {
        var app = launch()
        startRound(app, at: course)
        let score = element(app, "Score")
        XCTAssertTrue(score.waitForExistence(timeout: timeout))
        increase(score)
        increase(score)
        let expected = count(score)
        app.terminate()

        app = launch(reset: false)
        let restored = element(app, "Score")
        XCTAssertTrue(restored.waitForExistence(timeout: timeout), "A round changed in the last 12 hours reopens at launch")
        XCTAssertEqual(count(restored), expected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hole 1'")).firstMatch.exists)
    }

    func testMeasurePointDragsWithoutPanningTheMap() throws {
        let app = launch()
        startRound(app, at: course)
        XCTAssertTrue(element(app, "Score").waitForExistence(timeout: timeout))

        visibleMapPoint(app, x: 0.3, y: 0.6).tap()
        let point = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Measure point 1,'")).firstMatch
        XCTAssertTrue(point.waitForExistence(timeout: timeout))
        let before = (label: point.label, frame: point.frame)
        let green = app.descendants(matching: .any)["Green"].firstMatch
        let greenBefore = green.frame

        point.tap()
        XCTAssertTrue(app.staticTexts["Measure point 1"].waitForExistence(timeout: timeout), "Tapping a point selects it")
        point.tap()

        let start = point.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 80, dy: -80)))
        XCTAssertTrue(point.waitForExistence(timeout: timeout))
        XCTAssertNotEqual(point.label, before.label, "Dragging the point should change its distance")
        XCTAssertGreaterThan(abs(point.frame.midX - before.frame.midX), 40, "The point should follow the finger")
        XCTAssertEqual(green.frame.midX, greenBefore.midX, accuracy: 2, "The map should stay put while the point moves")
    }

    func testGreenCloseUpFlagDrags() throws {
        let app = launch()
        startRound(app, at: course)
        app.buttons["Green close-up"].tap()
        let flag = app.descendants(matching: .any)["Hole location flag"].firstMatch
        XCTAssertTrue(flag.waitForExistence(timeout: timeout))
        let reset = app.buttons["Reset"]
        XCTAssertFalse(reset.isEnabled)
        let before = flag.frame

        let start = flag.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 50, dy: 40)))
        XCTAssertTrue(reset.isEnabled, "Moving the flag enables Reset")
        XCTAssertEqual(flag.frame.midX, before.midX + 50, accuracy: 6, "The flag should follow the finger")

        reset.tap()
        XCTAssertEqual(flag.frame.midX, before.midX, accuracy: 6)
    }

    // MARK: Course editor

    func testTraceEditSaveAndPlayCourse() throws {
        let app = launch()
        let name = "UI Test Links"
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: timeout))
        app.navigationBars.buttons["Trace a course"].tap()
        allowLocationIfAsked(app)

        let nameField = app.textFields["Course name (required)"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(name + "\n")

        app.buttons["Green"].tap()
        app.buttons["Draw"].tap()
        let panel = app.textFields["Course name (required)"]
        for (x, y) in [(0.35, 0.35), (0.65, 0.35), (0.65, 0.75), (0.35, 0.75)] {
            visibleMapPoint(app, x: x, y: y, above: panel).tap()
        }
        XCTAssertTrue(text(app, containing: "Draw green · 4 points").waitForExistence(timeout: timeout))
        app.buttons["Save green"].tap()
        XCTAssertTrue(text(app, containing: "Hole 1 of 18 · 1 features").waitForExistence(timeout: timeout))

        app.buttons["Bunker"].tap()
        let stroke = visibleMapPoint(app, x: 0.12, y: 0.45, above: panel)
        stroke.press(forDuration: 0.05, thenDragTo: stroke.withOffset(CGVector(dx: 40, dy: 90)), withVelocity: 300, thenHoldForDuration: 0.1)
        let drawn = text(app, containing: "Draw bunker ·")
        XCTAssertTrue(drawn.waitForExistence(timeout: timeout))
        let drawnPoints = Int(drawn.label.split(separator: "·").last?.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(drawnPoints, 3, "A freehand stroke should add points along its path: \(drawn.label)")
        app.buttons["Clear"].tap()
        app.buttons["Green"].tap()

        app.buttons["green"].tap()
        XCTAssertTrue(text(app, containing: "Editing green · 4 points").waitForExistence(timeout: timeout))
        let vertex = app.descendants(matching: .any)["Point 1"].firstMatch
        XCTAssertTrue(vertex.waitForExistence(timeout: timeout))
        let start = vertex.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -60, dy: -40)))
        XCTAssertTrue(app.buttons["Undo"].isEnabled, "Dragging a vertex should record an undoable change")
        app.buttons["Save shape"].tap()

        app.navigationBars.buttons["Save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "The traced course should be listed on Home")

        row.press(forDuration: 1.0)
        app.buttons["Edit course"].tap()
        XCTAssertTrue(app.navigationBars["Edit course"].waitForExistence(timeout: timeout))
        XCTAssertTrue(text(app, containing: "Hole 1 of 1 · 1 features").waitForExistence(timeout: timeout))
        app.navigationBars.buttons["Close"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        app.buttons["Start at \(name)"].tap()
        XCTAssertTrue(element(app, "Score").waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hole 1'")).firstMatch.exists)
    }

    // MARK: Helpers

    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-healthWorkoutMode", "never"]
        if reset { app.launchArguments.append("-GolfMapUITestReset") }
        app.launch()
        return app
    }

    private func startRound(_ app: XCUIApplication, at course: String) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: timeout))
        search.tap()
        search.typeText(course)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", course)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        app.buttons["Start at \(course)"].tap()
        allowLocationIfAsked(app)
    }

    private func endRound(_ app: XCUIApplication, choice: String) {
        app.buttons["Round options"].tap()
        app.buttons["End round"].tap()
        let button = app.buttons[choice]
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        button.tap()
    }

    private func allowLocationIfAsked(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    /// A point in the part of the map above `panel` (the round's dock by default); the map extends beneath it.
    private func visibleMapPoint(_ app: XCUIApplication, x: CGFloat, y: CGFloat, above panel: XCUIElement? = nil) -> XCUICoordinate {
        let map = app.maps.firstMatch.frame
        let bottom = (panel ?? element(app, "Show hole details")).frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        return origin.withOffset(CGVector(dx: map.minX + map.width * x, dy: map.minY + (bottom - map.minY) * y))
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)[label].firstMatch
    }

    private func text(_ app: XCUIApplication, containing value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func count(_ stepper: XCUIElement) -> Int {
        Int((stepper.value as? String)?.split(separator: ",").first ?? "") ?? -1
    }

    /// The steppers are single adjustable elements, so tap their plus button by position.
    private func increase(_ stepper: XCUIElement) {
        stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
}
