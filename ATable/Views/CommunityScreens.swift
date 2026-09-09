import SwiftUI

struct ParentsScreen: View {
    @EnvironmentObject private var community: CommunityStore
    private let rooms = [
        ("general", "Entre parents", "Questions, entraide et petites infos du quotidien.", "bubble.left.and.bubble.right"),
        ("menus", "Autour des menus", "Les repas, les découvertes et les retours des enfants.", "fork.knife"),
        ("ideas", "La boîte à idées", "Des suggestions pour faire grandir À table.", "lightbulb")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Le coin des parents").font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text("Un espace pour échanger autour de la cantine de Montmagny.").foregroundStyle(.secondary)
                    if !community.configured {
                        Label("Ouverture prochaine des échanges", systemImage: "clock")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Palette.green)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    }
                    ForEach(rooms, id: \.0) { room in
                        NavigationLink { ConversationScreen(topic: room.0, title: room.1) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: room.3).font(.title2).foregroundStyle(Palette.green)
                                    .frame(width: 50, height: 54).background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(room.1).font(.headline).foregroundStyle(.primary)
                                    Text(room.2).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                    Text("Des échanges bienveillants, sans informations personnelles sur les enfants. Vous pourrez signaler un message ou bloquer un participant.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Palette.background).navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ConversationScreen: View {
    let topic: String
    let title: String
    @EnvironmentObject private var community: CommunityStore
    @State private var messages: [ParentMessage] = []
    @State private var draft = ""
    @State private var loading = false
    @State private var sending = false
    @State private var error: String?
    @State private var showAuth = false
    @State private var pendingBlock: ParentMessage?
    @State private var pendingReport: ParentMessage?

    var body: some View {
        Group {
            if !community.configured {
                ContentUnavailableView("Bientôt entre parents", systemImage: "bubble.left.and.bubble.right", description: Text("Les échanges en ligne ne sont pas encore ouverts dans cette première version. Les menus restent accessibles librement."))
            } else if !community.signedIn {
                VStack(spacing: 20) {
                    ContentUnavailableView("Rejoignez la conversation", systemImage: "person.crop.circle.badge.plus", description: Text("Un compte est nécessaire pour lire et publier les échanges entre parents."))
                    Button("Se connecter ou créer un compte") { showAuth = true }.buttonStyle(.borderedProminent)
                }.padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if loading { ProgressView().frame(maxWidth: .infinity) }
                            if messages.isEmpty && !loading {
                                ContentUnavailableView("La conversation commence ici", systemImage: "bubble.left", description: Text("Partagez une question ou une idée avec les autres parents."))
                            }
                            ForEach(messages) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(message.profiles?.nickname ?? "Parent").font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(readableTimestamp(message.created_at)).font(.caption2).foregroundStyle(.secondary)
                                        Menu {
                                            if message.user_id == community.userID {
                                                Button("Supprimer mon message", role: .destructive) { Task { await perform { try await community.deleteMessage(message) } } }
                                            } else {
                                                Button("Signaler ce message", role: .destructive) { pendingReport = message }
                                                Button("Bloquer ce participant", role: .destructive) { pendingBlock = message }
                                            }
                                        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                                    }
                                    Text(message.body).textSelection(.enabled)
                                }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 18)).id(message.id)
                            }
                        }.padding(18)
                    }
                    .refreshable { await reload() }
                    .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Votre message…", text: $draft, axis: .vertical).lineLimit(1...5)
                            .padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
                        Button {
                            guard !sending else { return }; sending = true
                            Task {
                                do { try await community.post(topic: topic, body: draft); draft = ""; await reload() }
                                catch { self.error = error.localizedDescription }
                                sending = false
                            }
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 38)) }
                            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                            .accessibilityLabel("Envoyer le message")
                    }.padding(14).background(.bar)
                }
            }
        }
        .background(Palette.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task(id: community.userID) { if community.signedIn { await reload() } }
        .sheet(isPresented: $showAuth) { AuthScreen() }
        .alert("Information", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("Signaler ce message à la modération ?", isPresented: Binding(get: { pendingReport != nil }, set: { if !$0 { pendingReport = nil } })) {
            Button("Signaler", role: .destructive) { if let message = pendingReport { Task { await perform { try await community.report(message) } } }; pendingReport = nil }
        }
        .confirmationDialog("Masquer les messages de ce participant ?", isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } })) {
            Button("Bloquer", role: .destructive) { if let message = pendingBlock { Task { await perform { try await community.block(message.user_id) } } }; pendingBlock = nil }
        }
    }
    private func reload() async {
        loading = true
        do { messages = try await community.messages(topic: topic) } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func perform(_ operation: () async throws -> Void) async {
        do { try await operation(); await reload() } catch { self.error = error.localizedDescription }
    }
}

struct AuthScreen: View {
    @EnvironmentObject private var community: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var busy = false
    @State private var error: String?
    @State private var accepted = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(creating ? "Bienvenue à table." : "Heureux de vous retrouver.").font(.title2.bold())
                    Text("Votre compte sert aux commentaires et aux échanges. Les menus restent accessibles sans connexion.").foregroundStyle(.secondary)
                }
                Section {
                    if creating { TextField("Prénom ou pseudo", text: $nickname).textContentType(.nickname) }
                    TextField("Adresse e-mail", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Mot de passe", text: $password).textContentType(creating ? .newPassword : .password)
                    if creating { Text("10 caractères minimum").font(.caption).foregroundStyle(.secondary) }
                }
                if creating { Section { Toggle("Je m’engage à respecter les autres et à ne pas publier d’informations personnelles sur les enfants.", isOn: $accepted) } }
                if let error { Text(error).foregroundStyle(Palette.red) }
                if let notice = community.notice { Text(notice).foregroundStyle(Palette.green) }
                Section {
                    Button {
                        busy = true; error = nil; community.notice = nil
                        Task {
                            do {
                                if creating { try await community.register(email: email, password: password, nickname: nickname) }
                                else { try await community.login(email: email, password: password) }
                                if community.signedIn { password = ""; dismiss() }
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: { HStack { Spacer(); if busy { ProgressView() } else { Text(creating ? "Créer mon compte" : "Me connecter").bold() }; Spacer() } }
                        .disabled(busy || email.isEmpty || password.isEmpty || (creating && !accepted) || !community.configured)
                    Button(creating ? "J’ai déjà un compte" : "Créer un compte") { creating.toggle(); error = nil; community.notice = nil }
                }
            }.navigationTitle(creating ? "Créer un compte" : "Connexion").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct ProfileScreen: View {
    @EnvironmentObject private var community: CommunityStore
    @AppStorage("showSnack") private var showSnack = true
    @AppStorage("appearance") private var appearance = "system"
    @State private var showAuth = false
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(Palette.green)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(community.signedIn ? "Mon compte" : "Bienvenue à table").font(.headline)
                            Text(community.session?.user.email ?? "Les menus sont accessibles librement.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                    if community.signedIn {
                        Button("Me déconnecter") { Task { await community.signOut() } }
                    } else if community.configured {
                        Button("Me connecter ou créer un compte") { showAuth = true }
                    } else { Text("Les comptes et les échanges ouvriront prochainement.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Ma lecture des menus") {
                    Toggle("Afficher les goûters", isOn: $showSnack)
                    Picker("Apparence", selection: $appearance) {
                        Text("Comme l’iPhone").tag("system")
                        Text("Claire").tag("light")
                        Text("Sombre").tag("dark")
                    }
                    NavigationLink("Comprendre les couleurs") { LegendSheet() }
                }
                Section("Ma cantine") {
                    LabeledContent("Ville", value: "Montmagny · 95360")
                    Text("Menus scolaires et centres de loisirs").foregroundStyle(.secondary)
                    Link("Programme de la mairie", destination: FoodiService.municipalURL)
                }
                Section("À propos") {
                    Text("À table est une application indépendante de lecture des menus de Montmagny. Les menus proviennent de Foodi ; les prévisions complémentaires sont publiées par la mairie.").font(.footnote)
                    Text("Version 0.1 · Première version iPhone").font(.caption).foregroundStyle(.secondary)
                }
                if community.signedIn {
                    Section {
                        Button("Supprimer mon compte", role: .destructive) { confirmDelete = true }
                    } footer: { Text("La suppression retire votre compte et vos messages de l’espace parents.") }
                }
                if let error { Text(error).foregroundStyle(Palette.red) }
            }
            .navigationTitle("Mon espace")
            .sheet(isPresented: $showAuth) { AuthScreen() }
            .confirmationDialog("Supprimer définitivement votre compte et vos messages ?", isPresented: $confirmDelete) {
                Button("Supprimer mon compte", role: .destructive) { Task { do { try await community.deleteAccount() } catch { self.error = error.localizedDescription } } }
            }
        }
    }
}
