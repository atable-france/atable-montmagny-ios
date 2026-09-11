import Foundation
import SwiftUI

enum FoodiError: LocalizedError {
    case invalidData, server(Int), api(String)
    var errorDescription: String? {
        switch self {
        case .invalidData: "Le menu reçu n’a pas le format attendu."
        case .server(let status): "Le service des menus est indisponible (\(status))."
        case .api: "Les menus ne sont pas accessibles pour le moment."
        }
    }
}

struct FoodiService {
    static let posID = "UG9zOjM4ODg1ODg="
    static let endpoint = URL(string: "https://api.foodi.fr/graphql")!
    static let municipalURL = URL(string: "https://www.villedemontmagny.fr/enfance/le-periscolaire/la-restauration-scolaire/")!

    func fetch(monday: Date) async throws -> WeekMenu {
        let dates = MenuDate.weekDates(monday)
        let fields = dates.enumerated().map { i, date in
            "jour\(i): menus(date: \"\(date)\") { day elements { id label description allergens certifications dish { id dishGroup { id } } } }"
        }.joined(separator: "\n")
        let query = "query MontmagnySemaine($id: ID!) { getPos(id: $id) { id name \(fields) } }"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["operationName": "MontmagnySemaine", "query": query, "variables": ["id": Self.posID]])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw FoodiError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FoodiError.invalidData }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty { throw FoodiError.api("GraphQL") }
        guard let root = json["data"] as? [String: Any], let pos = root["getPos"] as? [String: Any],
              pos["id"] as? String == Self.posID, let name = pos["name"] as? String else { throw FoodiError.invalidData }
        var days: [MenuDay] = []
        for (i, date) in dates.enumerated() {
            guard let menus = pos["jour\(i)"] as? [[String: Any]] else { throw FoodiError.invalidData }
            let value = try JSONSerialization.data(withJSONObject: menus)
            days.append(MenuDay(date: date, menus: try JSONDecoder().decode([DailyMenu].self, from: value)))
        }
        let week = WeekMenu(weekStart: dates[0], fetchedAt: ISO8601DateFormatter().string(from: Date()), restaurant: RestaurantRef(id: Self.posID, name: name), days: days)
        try week.validate(for: dates)
        return week
    }
}

private struct WebMenuItem: Decodable {
    let id: String
    let label: String
    let group: String
    let diet: Diet

    var native: MenuItem {
        let mapped: MealGroup
        switch group {
        case "starter": mapped = .starter
        case "main": mapped = .main
        case "side": mapped = .side
        case "dairy": mapped = .dairy
        case "dessert": mapped = .dessert
        default: mapped = .other
        }
        let encoded = Data("MenuElementDish:\(mapped.rawValue)".utf8).base64EncodedString()
        return MenuItem(id: id, label: label, description: nil, allergens: [], certifications: [], dish: DishRef(id: encoded, dishGroup: nil), reportedDiet: diet)
    }
}
private struct WebMenuDay: Decodable { let date: String; let items: [WebMenuItem] }
private struct WebWeekMenu: Decodable {
    let city: String
    let cityName: String
    let weekStart: String
    let fetchedAt: String
    let days: [WebMenuDay]

    var native: WeekMenu {
        WeekMenu(weekStart: weekStart, fetchedAt: fetchedAt, restaurant: RestaurantRef(id: city, name: cityName),
                 days: days.map { MenuDay(date: $0.date, menus: [DailyMenu(day: $0.date, elements: $0.items.map(\.native))]) })
    }
}

struct CityMenuService {
    private let config = BackendConfig.current
    func fetch(city: CanteenCity, level: SchoolLevel, monday: Date) async throws -> WeekMenu {
        if city == .montmagny { return try await FoodiService().fetch(monday: monday) }
        let configuredBase = config.menuAPIURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let base = configuredBase.isEmpty ? "https://www.mafabuleusecantine.com" : configuredBase
        guard var components = URLComponents(string: base + "/api/menus") else { throw FoodiError.api("Web") }
        components.queryItems = [
            URLQueryItem(name: "city", value: city.rawValue),
            URLQueryItem(name: "week", value: MenuDate.key(monday)),
            URLQueryItem(name: "level", value: level.rawValue)
        ]
        guard let url = components.url else { throw FoodiError.invalidData }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FoodiError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let value = try JSONDecoder().decode(WebWeekMenu.self, from: data).native
        try value.validate(for: MenuDate.weekDates(monday), restaurantID: city.rawValue)
        return value
    }

    func lookup(name: String, postalCode: String) async throws -> [CanteenCity] {
        let configuredBase = config.menuAPIURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let base = configuredBase.isEmpty ? "https://www.mafabuleusecantine.com" : configuredBase
        guard var components = URLComponents(string: base + "/api/cities/lookup") else { throw FoodiError.api("Web") }
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "postalCode", value: postalCode)]
        guard let url = components.url else { throw FoodiError.invalidData }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw FoodiError.server((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let result = try JSONDecoder().decode(CityLookupResponse.self, from: data)
        return result.candidates.compactMap(\.native)
    }
}

private struct CityLookupResponse: Decodable { let candidates: [CityLookupCandidate] }
private struct CityLookupCandidate: Decodable {
    let slug: String
    let name: String
    let postalCode: String
    let source: CityLookupSource
    var native: CanteenCity? {
        guard let url = URL(string: source.municipalUrl) else { return nil }
        return CanteenCity(rawValue: slug, name: name, postalCode: postalCode, supportsNursery: slug == "argenteuil", municipalURL: url)
    }
}
private struct CityLookupSource: Decodable { let municipalUrl: String }

@MainActor
final class MenuStore: ObservableObject {
    @Published var monday = MenuDate.monday(MenuDate.today)
    @Published var week: WeekMenu?
    @Published var loading = false
    @Published var stale = false
    @Published var message: String?
    @Published private(set) var city: CanteenCity
    @Published private(set) var schoolLevel: SchoolLevel
    private var generation = 0
    private let service = CityMenuService()

    var availableCities: [CanteenCity] {
        CanteenCity.allCases.contains(city) ? CanteenCity.allCases : CanteenCity.allCases + [city]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "selectedCity"), let saved = try? JSONDecoder().decode(CanteenCity.self, from: data) { city = saved }
        else { city = CanteenCity(rawValue: UserDefaults.standard.string(forKey: "citySlug") ?? "") ?? .montmagny }
        schoolLevel = SchoolLevel(rawValue: UserDefaults.standard.string(forKey: "schoolLevel") ?? "") ?? .elementary
    }

    func selectCity(_ value: CanteenCity) {
        guard city != value else { return }
        city = value
        if !value.supportsNursery { schoolLevel = .elementary }
        UserDefaults.standard.set(city.rawValue, forKey: "citySlug")
        if let data = try? JSONEncoder().encode(city) { UserDefaults.standard.set(data, forKey: "selectedCity") }
        UserDefaults.standard.set(schoolLevel.rawValue, forKey: "schoolLevel")
        week = nil; message = nil; generation += 1
    }
    func findCities(name: String, postalCode: String) async throws -> [CanteenCity] {
        let value = try await service.lookup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), postalCode: postalCode)
        if value.isEmpty { throw FoodiError.api("Aucune source publique") }
        return value
    }
    func selectSchoolLevel(_ value: SchoolLevel) {
        guard schoolLevel != value else { return }
        schoolLevel = value
        UserDefaults.standard.set(value.rawValue, forKey: "schoolLevel")
        week = nil; message = nil; generation += 1
    }

    func move(_ offset: Int) { monday = MenuDate.add(offset * 7, to: monday) }
    func currentWeek() { monday = MenuDate.monday(MenuDate.today) }
    private func file(for key: String) -> URL? {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = root.appendingPathComponent("Menus-\(city.rawValue)-\(schoolLevel.rawValue)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(key + ".json")
    }
    private func cached(_ key: String) -> WeekMenu? {
        if let url = file(for: key), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(WeekMenu.self, from: data),
           (try? value.validate(for: MenuDate.weekDates(monday), restaurantID: city == .montmagny ? FoodiService.posID : city.rawValue)) != nil { return value }
        if city == .montmagny, let url = Bundle.main.url(forResource: "menus-seed", withExtension: "json"),
           let data = try? Data(contentsOf: url), let seed = try? JSONDecoder().decode(MenuSeed.self, from: data),
           let value = seed.weeks.first(where: { $0.weekStart == key }),
           (try? value.validate(for: MenuDate.weekDates(monday))) != nil { return value }
        return nil
    }
    func load(force: Bool = false) async {
        generation += 1
        let requestID = generation
        let requestedMonday = monday
        let key = MenuDate.key(requestedMonday)
        let previous = cached(key)
        week = previous; message = nil; stale = previous != nil
        if ProcessInfo.processInfo.arguments.contains("--screenshots") {
            loading = false; stale = true; return
        }
        if !force, let previous, let date = ISO8601DateFormatter().date(from: previous.fetchedAt),
           Date().timeIntervalSince(date) >= 0, Date().timeIntervalSince(date) < 3600 {
            loading = false; stale = false; return
        }
        loading = true
        do {
            let requestedCity = city, requestedLevel = schoolLevel
            let fresh = try await service.fetch(city: requestedCity, level: requestedLevel, monday: requestedMonday)
            guard generation == requestID, !Task.isCancelled else { return }
            week = fresh; stale = false
            if let path = file(for: key), let data = try? JSONEncoder().encode(fresh) { try? data.write(to: path, options: .atomic) }
        } catch {
            guard generation == requestID, !Task.isCancelled else { return }
            message = previous == nil ? "Connexion impossible. Réessayez dans un instant." : "Derniers menus enregistrés. La mise à jour est indisponible."
            stale = true
        }
        if generation == requestID { loading = false }
    }
}
