import XCTest
@testable import ATable

final class MenuTests: XCTestCase {
    func testDietAlternativesAndAmbiguity() {
        XCTAssertEqual(Diet.classify("CHILI CON CARNE*"), .meat)
        XCTAssertEqual(Diet.classify("Chili sin carné"), .vegetarian)
        XCTAssertEqual(Diet.classify("Bolognaise de lentilles"), .vegetarian)
        XCTAssertEqual(Diet.classify("Filet de colin sauce crème"), .fish)
        XCTAssertEqual(Diet.classify("Poulet basquaise"), .meat)
        XCTAssertEqual(Diet.classify("Omelette au jambon"), .meat)
        XCTAssertEqual(Diet.classify("Omelette au thon"), .fish)
        XCTAssertEqual(Diet.classify("Émincé VG BIO sauce forestière"), .vegetarian)
        XCTAssertEqual(Diet.classify("Boulettes sauce maison"), .unknown)
        XCTAssertEqual(Diet.classify("Raviolis"), .unknown)
        XCTAssertEqual(Diet.classify("Bœuf aux carottes"), .meat)
    }
    func testDatesAcrossParisDaylightSaving() {
        let monday = MenuDate.monday(MenuDate.parse("2026-03-29")!)
        XCTAssertEqual(MenuDate.key(monday), "2026-03-23")
        XCTAssertEqual(MenuDate.weekDates(MenuDate.parse("2026-03-30")!), ["2026-03-30", "2026-03-31", "2026-04-01", "2026-04-02", "2026-04-03"])
        XCTAssertEqual(MenuDate.key(MenuDate.add(7, to: monday)), "2026-03-30")
    }
    func testBundledDataAndRestaurantValidation() throws {
        let url = Bundle.main.url(forResource: "menus-seed", withExtension: "json")!
        let seed = try JSONDecoder().decode(MenuSeed.self, from: Data(contentsOf: url))
        XCTAssertEqual(seed.weeks.count, 7)
        for week in seed.weeks { try week.validate(for: MenuDate.weekDates(MenuDate.parse(week.weekStart)!)) }
        let week = seed.weeks.first { $0.weekStart == "2026-09-07" }!
        XCTAssertEqual(week.days.count, 5)
        XCTAssertTrue(week.days[2].items(.main).contains { $0.diet == .meat })
        XCTAssertTrue(week.days[2].items(.main).contains { $0.diet == .vegetarian })
        let bad = WeekMenu(weekStart: week.weekStart, fetchedAt: week.fetchedAt, restaurant: RestaurantRef(id: "wrong", name: "Other"), days: week.days)
        XCTAssertThrowsError(try bad.validate(for: MenuDate.weekDates(MenuDate.parse(week.weekStart)!)))
    }
}
