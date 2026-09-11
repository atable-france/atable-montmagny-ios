import SwiftUI

struct MenuScreen: View {
    @EnvironmentObject private var store: MenuStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("showSnack") private var showSnack = true
    @AppStorage("dietOverrides") private var overrides = "{}"
    @State private var mode = 0
    @State private var selectedDate = MenuDate.key(MenuDate.today)
    @State private var selectedItem: MenuItem?
    @State private var showLegend = false
    @State private var showCitySearch = false

    private var dates: [String] { MenuDate.weekDates(store.monday) }
    private var selectedDay: MenuDay? { store.week?.days.first { $0.date == selectedDate } }
    private var weekLabel: String {
        "\(MenuDate.label(store.monday, format: "d")) – \(MenuDate.label(MenuDate.add(4, to: store.monday), format: "d MMMM yyyy"))"
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        masthead
                        citySelector
                        weekNavigation
                        Picker("Affichage des menus", selection: $mode) {
                            Text("Semaine").tag(0)
                            Text("Jour").tag(1)
                        }.pickerStyle(.segmented).accessibilityIdentifier("menuMode")
                        if store.loading && store.week == nil {
                            ProgressView("Les menus arrivent…").frame(maxWidth: .infinity, minHeight: 220)
                        } else if let week = store.week, week.hasFood {
                            legend
                            if mode == 0 && !typeSize.isAccessibilitySize {
                                schedule(width: geometry.size.width)
                            } else {
                                dayPicker
                                dayContent
                            }
                            sourceStatus
                        } else {
                            emptyWeek
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 32)
                    .frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }
                .background(Palette.background)
                .refreshable { await store.load(force: true) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(store.city.rawValue)-\(store.schoolLevel.rawValue)-\(MenuDate.key(store.monday))") {
                if !dates.contains(selectedDate) { selectedDate = dates[0] }
                await store.load()
            }
            .sheet(item: $selectedItem) { item in DishDetail(item: item) }
            .sheet(isPresented: $showLegend) { LegendSheet() }
            .sheet(isPresented: $showCitySearch) { CitySearchView() }
        }
    }

    private var masthead: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(store.city.name.uppercased()) · \(store.city.postalCode)").font(.caption.weight(.semibold)).tracking(1.8).foregroundStyle(Palette.green)
                Text("À table.").font(.system(size: 40, weight: .bold, design: .serif)).accessibilityIdentifier("appTitle")
                Text("Les menus, en un coup d’œil.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "fork.knife.circle.fill").font(.system(size: 48)).foregroundStyle(Palette.green).accessibilityHidden(true)
        }
    }

    private var citySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(store.availableCities) { city in
                    Button {
                        store.selectCity(city)
                    } label: {
                        if city == store.city { Label("\(city.name) · \(city.postalCode)", systemImage: "checkmark") }
                        else { Text("\(city.name) · \(city.postalCode)") }
                    }
                }
                Divider()
                Button { showCitySearch = true } label: { Label("Ajouter une ville", systemImage: "magnifyingglass") }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ma ville").font(.caption).foregroundStyle(.secondary)
                        Text("\(store.city.name) · \(store.city.postalCode)").font(.headline).foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.padding(15).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            }.accessibilityIdentifier("citySelector")
            if store.city.supportsNursery {
                Picker("Établissement", selection: Binding(get: { store.schoolLevel }, set: { store.selectSchoolLevel($0) })) {
                    ForEach(SchoolLevel.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("schoolLevel")
            }
        }
    }

    private var weekNavigation: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { store.move(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 48)
                }.accessibilityLabel("Semaine précédente").accessibilityIdentifier("previousWeek")
                VStack(spacing: 4) {
                    Text("SEMAINE \(MenuDate.calendar.component(.weekOfYear, from: store.monday))")
                        .font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                    Text(weekLabel).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity)
                Button { store.move(1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 48)
                }.accessibilityLabel("Semaine suivante").accessibilityIdentifier("nextWeek")
            }.tint(.primary).padding(8).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            if MenuDate.key(store.monday) != MenuDate.key(MenuDate.monday(MenuDate.today)) {
                Button("Revenir à cette semaine") { store.currentWeek() }.font(.subheadline.weight(.medium))
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label("Viande", systemImage: "circle.fill").foregroundStyle(Palette.red)
                Label("Végé / poisson", systemImage: "circle.fill").foregroundStyle(Palette.green)
                Spacer(minLength: 0)
                Button { showLegend = true } label: { Image(systemName: "info.circle").frame(width: 28, height: 32) }
                    .accessibilityLabel("Comprendre les couleurs")
            }.font(.caption.weight(.medium))
            if mode == 0 && !typeSize.isAccessibilitySize {
                Text("Balayez le tableau pour parcourir les cinq jours.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func schedule(width: CGFloat) -> some View {
        let columnWidth = max(220, min(290, (width - 48) * 0.73))
        let groups = MealGroup.displayOrder.filter { group in
            (showSnack || group != .snack) && store.week!.days.contains { !$0.items(group).isEmpty }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.week!.days) { day in
                    VStack(spacing: 0) {
                        dayHeader(day.date)
                        if day.elements.isEmpty {
                            Text("Menu non disponible").foregroundStyle(.secondary).padding(20).frame(minHeight: 160)
                        } else {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(group.label.uppercased(), systemImage: group.icon)
                                        .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                                    let items = day.items(group)
                                    if items.isEmpty { Text("—").foregroundStyle(.tertiary) }
                                    ForEach(items) { item in
                                        dishButton(item, compact: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: rowHeight(group), alignment: .topLeading)
                                .overlay(alignment: .bottom) { Divider().padding(.horizontal, 14) }
                            }
                        }
                        Button {
                            selectedDate = day.date; mode = 1
                        } label: { Label("Voir la journée", systemImage: "arrow.up.right").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(16) }
                    }
                    .frame(width: columnWidth)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(day.date == MenuDate.key(MenuDate.today) ? Palette.green.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1))
                }
            }.padding(.bottom, 4)
        }.accessibilityIdentifier("weekSchedule")
    }
    private func rowHeight(_ group: MealGroup) -> CGFloat {
        let count = store.week?.days.map { $0.items(group).count }.max() ?? 1
        return CGFloat(max(1, count)) * (group == .main ? 94 : 68) + 48
    }
    private func dayHeader(_ key: String) -> some View {
        let date = MenuDate.parse(key)!
        let today = key == MenuDate.key(MenuDate.today)
        return HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(MenuDate.label(date, format: "EEEE").capitalized).font(.headline)
                Text(MenuDate.label(date, format: "d MMMM")).font(.caption)
            }
            Spacer()
            if today { Text("AUJ.").font(.caption2.weight(.bold)).padding(7).background(.white.opacity(0.18), in: Capsule()) }
        }.padding(16).foregroundStyle(today ? Color.white : Color.primary)
            .background(today ? Palette.green : Palette.green.opacity(0.08))
    }
    private func dishButton(_ item: MenuItem, compact: Bool = false) -> some View {
        let diet = effectiveDiet(item)
        return Button { selectedItem = item } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(compact ? .subheadline.weight(.medium) : .body.weight(.medium))
                    .foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if diet != .unknown || item.group == .main {
                    DietBadge(diet: diet)
                }
            }.padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(diet.color.opacity(diet == .unknown ? 0.3 : 0.8)).frame(width: 3)
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(item.title), \(diet.label), détails")
    }
    private func effectiveDiet(_ item: MenuItem) -> Diet {
        let data = Data(overrides.utf8)
        let values = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        return values[item.id].flatMap(Diet.init(rawValue:)) ?? item.diet
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(dates, id: \.self) { key in
                    let date = MenuDate.parse(key)!
                    Button { selectedDate = key } label: {
                        VStack(spacing: 7) {
                            Text(MenuDate.label(date, format: "EEE").uppercased()).font(.caption2.weight(.bold))
                            Text(MenuDate.label(date, format: "d")).font(.title3.weight(.semibold))
                        }.frame(minWidth: 53).padding(.vertical, 13)
                            .foregroundStyle(selectedDate == key ? .white : .primary)
                            .background(selectedDate == key ? Palette.green : Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    }.accessibilityLabel(MenuDate.label(date, format: "EEEE d MMMM"))
                }
            }
        }
    }
    @ViewBuilder private var dayContent: some View {
        if let day = selectedDay, !day.elements.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MealGroup.displayOrder.filter { (showSnack || $0 != .snack) && !day.items($0).isEmpty }) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        Label(group.label, systemImage: group.icon).font(.headline).foregroundStyle(Palette.green)
                        ForEach(day.items(group)) { dishButton($0) }
                    }.padding(20)
                    Divider().padding(.horizontal, 20)
                }
            }.background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            NavigationLink {
                ConversationScreen(topic: "menu:\(selectedDate)", title: "Menu du \(MenuDate.label(MenuDate.parse(selectedDate)!, format: "d MMMM"))")
            } label: {
                Label("Commenter ce menu", systemImage: "bubble.left").font(.headline).frame(maxWidth: .infinity).padding(16)
            }.buttonStyle(.bordered).tint(Palette.green)
        } else {
            ContentUnavailableView("Menu non disponible", systemImage: "calendar.badge.clock", description: Text("Aucun plat n’est retourné pour cette journée."))
            Link("Consulter le programme de la mairie", destination: store.city.municipalURL)
        }
    }
    private var sourceStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.stale ? "Copie enregistrée" : "Menus à jour", systemImage: store.stale ? "clock.arrow.circlepath" : "checkmark.circle")
                .font(.caption.weight(.semibold)).foregroundStyle(store.stale ? Palette.amber : Palette.green)
            if let text = store.message { Text(text).font(.caption).foregroundStyle(.secondary) }
            if let timestamp = store.week?.fetchedAt {
                Text("Dernière récupération : \(readableTimestamp(timestamp))").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Les alternatives restent présentées séparément. Touchez un plat pour consulter ses détails.").font(.caption).foregroundStyle(.secondary)
            Button { Task { await store.load(force: true) } } label: {
                Label(store.loading ? "Actualisation…" : "Actualiser les menus", systemImage: "arrow.clockwise")
            }.font(.subheadline).disabled(store.loading).padding(.top, 2)
        }
    }
    private var emptyWeek: some View {
        VStack(spacing: 20) {
            ContentUnavailableView("Les menus se préparent", systemImage: "calendar.badge.clock", description: Text(store.message ?? "Aucun menu n’est encore publié pour cette semaine. Le programme prévisionnel peut être disponible à la mairie."))
            Link(destination: store.city.municipalURL) {
                Label("Voir le programme de la mairie", systemImage: "doc.text").frame(maxWidth: .infinity).padding(12)
            }.buttonStyle(.borderedProminent)
            Button("Réessayer") { Task { await store.load(force: true) } }.disabled(store.loading)
        }.padding(.vertical, 20)
    }
}

private struct CitySearchView: View {
    @EnvironmentObject private var store: MenuStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var postalCode = ""
    @State private var choices: [CanteenCity] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Votre commune") {
                    TextField("Ville", text: $name).textContentType(.addressCity)
                    TextField("Code postal", text: $postalCode).keyboardType(.numberPad).textContentType(.postalCode)
                    Button {
                        loading = true; error = nil; choices = []
                        Task {
                            do {
                                let found = try await store.findCities(name: name, postalCode: postalCode)
                                if found.count == 1 { store.selectCity(found[0]); dismiss() }
                                else { choices = found }
                            } catch { self.error = "Aucune source de menu publique n’a été trouvée pour cette commune." }
                            loading = false
                        }
                    } label: { if loading { ProgressView() } else { Label("Rechercher les menus", systemImage: "magnifyingglass") } }
                    .disabled(loading || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || postalCode.count != 5)
                }
                if !choices.isEmpty {
                    Section("Cantines trouvées") {
                        ForEach(choices) { city in
                            Button("\(city.name) · \(city.postalCode)") { store.selectCity(city); dismiss() }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Palette.red) } }
                Section { Text("L’application vérifie Foodi puis les publications officielles de la mairie. Certains prestataires demandent ensuite un compte.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Ajouter ma ville")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

func readableTimestamp(_ value: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    return date.map { MenuDate.label($0, format: "d MMM à HH:mm") } ?? value
}

extension Diet {
    var color: Color {
        switch self { case .meat: Palette.red; case .fish, .vegetarian: Palette.green; case .unknown: .secondary }
    }
}
struct DietBadge: View {
    let diet: Diet
    var body: some View {
        Label(diet.label, systemImage: diet.icon).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(diet.color).background(diet.color.opacity(0.09), in: Capsule())
    }
}

struct LegendSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Les repères du menu") {
                    ForEach(Diet.allCases, id: \.self) { DietBadge(diet: $0).padding(.vertical, 6) }
                }
                Section {
                    Text("Le rouge indique de la viande. Le vert indique un plat végétarien ou du poisson, avec un libellé distinct.")
                    Text("Les repères sont estimés à partir du nom du plat. Une recette ambiguë reste « À vérifier ». Vous pouvez ajuster un repère sur cet iPhone depuis la fiche du plat.")
                    Text("Un repère de couleur ne remplace pas la liste des ingrédients ou des allergènes.")
                }
            }.navigationTitle("Comprendre les couleurs").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct DishDetail: View {
    let item: MenuItem
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dietOverrides") private var overrides = "{}"
    private var values: [String: String] { (try? JSONDecoder().decode([String: String].self, from: Data(overrides.utf8))) ?? [:] }
    private var diet: Diet { values[item.id].flatMap(Diet.init(rawValue:)) ?? item.diet }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.title).font(.title2.weight(.bold)).padding(.vertical, 6)
                    DietBadge(diet: diet)
                    if let description = item.description, description != item.label { Text(description) }
                }
                Section("Allergènes communiqués par Foodi") {
                    if item.allergens.isEmpty { Text("Information non communiquée").foregroundStyle(.secondary) }
                    ForEach(item.allergens, id: \.self) { Text(allergenLabel($0)) }
                }
                if !item.certifications.isEmpty {
                    Section("Labels communiqués") {
                        ForEach(item.certifications, id: \.self) { Text(certificationLabel($0)) }
                    }
                }
                Section {
                    Picker("Mon repère", selection: Binding(get: { diet }, set: { value in
                        var next = values; next[item.id] = value.rawValue
                        if let data = try? JSONEncoder().encode(next) { overrides = String(decoding: data, as: UTF8.self) }
                    })) { ForEach(Diet.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if values[item.id] != nil {
                        Button("Rétablir le repère estimé") {
                            var next = values; next.removeValue(forKey: item.id)
                            if let data = try? JSONEncoder().encode(next) { overrides = String(decoding: data, as: UTF8.self) }
                        }
                    }
                } header: { Text("Ajuster sur cet iPhone") } footer: {
                    Text("Ce choix reste personnel. Il ne modifie pas le menu Foodi. Le repère initial est une estimation d’après le nom du plat.")
                }
            }.navigationTitle("Le détail du plat").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

func allergenLabel(_ code: String) -> String {
    ["GLUTEN": "Gluten", "EGG": "Œufs", "MILK": "Lait", "FISH": "Poisson", "SOY": "Soja", "SOYA": "Soja", "SESAME": "Sésame", "MUSTARD": "Moutarde", "CELERY": "Céleri", "NUTS": "Fruits à coque", "PEANUT": "Arachide", "PEANUTS": "Arachides", "SULPHITES": "Sulfites", "LUPIN": "Lupin", "CRUSTACEANS": "Crustacés", "MOLLUSCS": "Mollusques", "INFO_NOT_DISCLOSED": "Information non communiquée", "ALLERGEN_FREE": "Mention fournisseur : sans allergène déclaré"][code] ?? code
}
func certificationLabel(_ code: String) -> String {
    ["BIO": "Agriculture biologique", "HVE": "Haute valeur environnementale", "IGP": "Indication géographique protégée", "AOP": "Appellation d’origine protégée", "RED_LABEL": "Label Rouge", "BLUE_WHITE_HEARTH": "Bleu-Blanc-Cœur", "VBF": "Viande bovine française"][code] ?? code
}
