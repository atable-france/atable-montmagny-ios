import SwiftUI

@main
struct ATableApp: App {
    @StateObject private var menus = MenuStore()
    @StateObject private var community = CommunityStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            TabView {
                MenuScreen()
                    .tabItem { Label("Menus", systemImage: "calendar") }
                ParentsScreen()
                    .tabItem { Label("Parents", systemImage: "bubble.left.and.bubble.right") }
                ProfileScreen()
                    .tabItem { Label("Mon espace", systemImage: "person.crop.circle") }
            }
            .tint(Palette.green)
            .environmentObject(menus)
            .environmentObject(community)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .task { await community.restoreSession() }
        }
    }
}

enum Palette {
    static let green = Color(red: 0.13, green: 0.40, blue: 0.31)
    static let red = Color(red: 0.71, green: 0.18, blue: 0.22)
    static let amber = Color(red: 0.61, green: 0.39, blue: 0.10)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}
