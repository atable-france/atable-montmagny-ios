import XCTest

final class ATableUITests: XCTestCase {
    @MainActor
    func testMenusNavigationAndProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.scrollViews["weekSchedule"].exists)
        app.buttons["nextWeek"].tap()
        XCTAssertTrue(app.staticTexts["14 – 18 septembre 2026"].waitForExistence(timeout: 5))
        app.buttons["previousWeek"].tap()
        app.segmentedControls["menuMode"].buttons["Jour"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Filet de colin")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Mon espace"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ma lecture des menus")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Parents"].tap()
        XCTAssertTrue(app.staticTexts["Le coin des parents"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Menus"].tap()
        app.segmentedControls["menuMode"].buttons["Semaine"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Menus - iPhone"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
