import Foundation

enum MenuDate {
    static var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(identifier: "Europe/Paris")!
        value.firstWeekday = 2
        return value
    }
    static var formatter: DateFormatter {
        let value = DateFormatter()
        value.calendar = calendar
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = calendar.timeZone
        value.dateFormat = "yyyy-MM-dd"
        return value
    }
    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func parse(_ key: String) -> Date? { formatter.date(from: key) }
    static func monday(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)!.start }
    static func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    static func weekDates(_ monday: Date) -> [String] { (0..<5).map { key(add($0, to: monday)) } }
    static func label(_ date: Date, format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.timeZone = calendar.timeZone; f.dateFormat = format
        return f.string(from: date)
    }
    static var today: Date {
        if ProcessInfo.processInfo.arguments.contains("--screenshots") { return parse("2026-09-09")! }
        return Date()
    }
}

struct DishRef: Codable, Hashable { let id: String; let dishGroup: IDRef? }
struct IDRef: Codable, Hashable { let id: String }
struct MenuItem: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let description: String?
    let allergens: [String]
    let certifications: [String]
    let dish: DishRef?
    let reportedDiet: Diet?

    var group: MealGroup {
        guard let id = dish?.id, let data = Data(base64Encoded: id), let text = String(data: data, encoding: .utf8),
              text.hasPrefix("MenuElementDish:"), let code = Int(text.split(separator: ":").last ?? "") else { return .other }
        return MealGroup(rawValue: code) ?? .other
    }
    var title: String {
        let value = label.replacingOccurrences(of: "/*", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " *"))
        return value == value.uppercased() ? value.lowercased().prefix(1).uppercased() + value.lowercased().dropFirst() : value
    }
    var diet: Diet { reportedDiet ?? Diet.classify(label) }
}

enum CanteenCity: String, CaseIterable, Identifiable {
    case montmagny, argenteuil
    var id: String { rawValue }
    var name: String { self == .montmagny ? "Montmagny" : "Argenteuil" }
    var postalCode: String { self == .montmagny ? "95360" : "95100" }
    var supportsNursery: Bool { self == .argenteuil }
    var municipalURL: URL {
        switch self {
        case .montmagny: URL(string: "https://www.villedemontmagny.fr/enfance/le-periscolaire/la-restauration-scolaire/")!
        case .argenteuil: URL(string: "https://www.argenteuil.fr/fr/restauration-scolaire")!
        }
    }
}

enum SchoolLevel: String, CaseIterable, Identifiable {
    case elementary, nursery
    var id: String { rawValue }
    var label: String { self == .elementary ? "Élémentaire" : "Maternelle" }
}

enum MealGroup: Int, CaseIterable, Identifiable {
    case starter = 529, main = 530, dessert = 531, bread = 532, dairy = 533, side = 534, snack = 535, other = 0
    var id: Int { rawValue }
    static let displayOrder: [MealGroup] = [.starter, .main, .side, .dairy, .dessert, .bread, .snack, .other]
    var label: String {
        switch self {
        case .starter: "Entrée"
        case .main: "Plat"
        case .side: "Accompagnement"
        case .dairy: "Laitage"
        case .dessert: "Dessert"
        case .bread: "Pain"
        case .snack: "Goûter"
        case .other: "Au menu"
        }
    }
    var icon: String {
        switch self {
        case .starter: "carrot"
        case .main: "fork.knife"
        case .side: "leaf"
        case .dairy: "mug"
        case .dessert: "birthday.cake"
        case .bread: "basket"
        case .snack: "sun.haze"
        case .other: "list.bullet"
        }
    }
}

enum Diet: String, Codable, CaseIterable {
    case meat, vegetarian, fish, unknown
    var label: String {
        switch self { case .meat: "Viande"; case .vegetarian: "Végétarien"; case .fish: "Poisson"; case .unknown: "À vérifier" }
    }
    var icon: String {
        switch self { case .meat: "fork.knife"; case .vegetarian: "leaf.fill"; case .fish: "fish.fill"; case .unknown: "questionmark.circle" }
    }
    // Conservative label-based guidance. Unknown recipes remain unknown; absence of a meat keyword is not proof.
    static func classify(_ text: String) -> Diet {
        let t = " " + text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression) + " "
        let vegetarianNames = ["chili sin carne", "bolognaise de lentilles", "tajine de pois chiches", "haricot blanc a la basquaise", "haricots blancs basquaise", "paleron vegetal"]
        let meat = ["boeuf", "bœuf", "veau", "porc", "poulet", "dinde", "volaille", "agneau", "mouton", "canard", "jambon", "lardon", "lardons", "saucisse", "saucisses", "chorizo", "merguez", "bacon", "lapin", "chili con carne"]
        let fish = ["poisson", "colin", "hoki", "merlu", "lieu", "cabillaud", "saumon", "thon", "sardine", "truite", "morue", "anchois", "crevette", "moule", "surimi"]
        // Explicit replacements are recognised only when no real meat/fish is also named.
        let explicitVegetarian = t.contains(" vegetarien ") || t.contains(" vegetarienne ") || t.contains(" vg ") || t.contains(" vegetal ") || t.contains(" vegetale ")
        let hasMeat = meat.contains { t.contains(" " + $0 + " ") }
        let hasFish = fish.contains { t.contains(" " + $0 + " ") }
        if explicitVegetarian && !hasMeat && !hasFish { return .vegetarian }
        if hasMeat { return .meat }
        if hasFish { return .fish }
        if vegetarianNames.contains(where: { t.contains(" " + $0 + " ") }) { return .vegetarian }
        if t.contains(" omelette ") || t.contains(" crousti fromage ") { return .vegetarian }
        return .unknown
    }
}

struct DailyMenu: Codable { let day: String; let elements: [MenuItem] }
struct MenuDay: Codable, Identifiable {
    let date: String
    let menus: [DailyMenu]
    var id: String { date }
    var elements: [MenuItem] {
        var seen = Set<String>()
        return menus.flatMap(\.elements).filter { seen.insert($0.id).inserted }
    }
    func items(_ group: MealGroup) -> [MenuItem] { elements.filter { $0.group == group } }
}
struct WeekMenu: Codable {
    let weekStart: String
    let fetchedAt: String
    let restaurant: RestaurantRef
    let days: [MenuDay]
    var hasFood: Bool { days.contains { !$0.elements.isEmpty } }
    func validate(for dates: [String], restaurantID: String = FoodiService.posID) throws {
        guard restaurant.id == restaurantID, days.map(\.date) == dates else { throw FoodiError.invalidData }
        guard days.allSatisfy({ day in day.menus.allSatisfy { $0.day == day.date } }) else { throw FoodiError.invalidData }
    }
}
struct RestaurantRef: Codable { let id: String; let name: String }
struct MenuSeed: Codable { let weeks: [WeekMenu] }
