import Foundation
import Security
import SwiftUI

struct BackendConfig: Decodable {
    let url: String
    let publishableKey: String
    static var current: Self {
        guard let path = Bundle.main.url(forResource: "Backend", withExtension: "json"),
              let data = try? Data(contentsOf: path), let config = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(url: "", publishableKey: "")
        }
        return config
    }
    var enabled: Bool { URL(string: url)?.scheme == "https" && !publishableKey.isEmpty }
}
struct ParentUser: Codable { let id: UUID; let email: String? }
struct ParentSession: Codable {
    let access_token: String
    let refresh_token: String
    let expires_at: Double?
    let user: ParentUser
}
struct ParentMessage: Codable, Identifiable {
    let id: UUID
    let user_id: UUID
    let topic: String
    let body: String
    let created_at: String
    let profiles: PublicProfile?
}
struct PublicProfile: Codable { let nickname: String }
struct CommunityError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum SessionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.atable.montmagny", kSecAttrAccount as String: "session"]
    }
    static func read() -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
    static func save(_ data: Data) {
        var q = query; SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var session: ParentSession?
    @Published var busy = false
    @Published var notice: String?
    private let config = BackendConfig.current
    var configured: Bool { config.enabled }
    var signedIn: Bool { session != nil }
    var userID: UUID? { session?.user.id }

    func restoreSession() async {
        guard configured, let data = SessionKeychain.read(), let saved = try? JSONDecoder().decode(ParentSession.self, from: data) else { return }
        session = saved
        do { try await refreshIfNeeded() } catch { session = nil; SessionKeychain.clear() }
    }
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = false) async throws -> Data {
        guard configured, let url = URL(string: config.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw CommunityError(message: "L’espace parents n’est pas encore ouvert.")
        }
        if authenticated { try await refreshIfNeeded() }
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 20
        r.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session else { throw CommunityError(message: "Connectez-vous pour participer.") }
            r.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization")
        }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw CommunityError(message: "Connexion indisponible.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw CommunityError(message: "Vérifiez votre connexion et la confirmation de votre adresse e-mail.") }
            if http.statusCode == 429 { throw CommunityError(message: "Trop de demandes. Réessayez dans un instant.") }
            throw CommunityError(message: "La demande n’a pas abouti. Vérifiez vos informations puis réessayez.")
        }
        return data
    }
    private func saveSession(_ data: Data) throws {
        let next = try JSONDecoder().decode(ParentSession.self, from: data)
        session = next; SessionKeychain.save(data)
    }
    private func refreshIfNeeded() async throws {
        guard let session else { throw CommunityError(message: "Connectez-vous pour participer.") }
        if let expiration = session.expires_at, expiration > Date().timeIntervalSince1970 + 60 { return }
        let data = try await request("/auth/v1/token?grant_type=refresh_token", method: "POST", body: ["refresh_token": session.refresh_token])
        try saveSession(data)
    }
    func login(email: String, password: String) async throws {
        let data = try await request("/auth/v1/token?grant_type=password", method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        try saveSession(data)
    }
    func register(email: String, password: String, nickname: String) async throws {
        guard (2...40).contains(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count), password.count >= 10 else {
            throw CommunityError(message: "Choisissez un prénom ou pseudo de 2 à 40 caractères et un mot de passe d’au moins 10 caractères.")
        }
        let data = try await request("/auth/v1/signup", method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "data": ["nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines)]])
        if (try? JSONDecoder().decode(ParentSession.self, from: data)) != nil { try saveSession(data) }
        else { notice = "Consultez vos e-mails pour confirmer votre adresse, puis connectez-vous." }
    }
    func signOut() async {
        _ = try? await request("/auth/v1/logout", method: "POST", authenticated: true)
        session = nil; SessionKeychain.clear()
    }
    func deleteAccount() async throws {
        _ = try await request("/rest/v1/rpc/delete_my_account", method: "POST", body: [:], authenticated: true)
        session = nil; SessionKeychain.clear()
    }
    func messages(topic: String) async throws -> [ParentMessage] {
        let encoded = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let data = try await request("/rest/v1/messages?select=id,user_id,topic,body,created_at,profiles(nickname)&topic=eq.\(encoded)&order=created_at.desc&limit=100", authenticated: true)
        return try JSONDecoder().decode([ParentMessage].self, from: data).reversed()
    }
    func post(topic: String, body: String) async throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2000).contains(text.count), let userID else { throw CommunityError(message: "Écrivez un message de 1 à 2 000 caractères.") }
        _ = try await request("/rest/v1/messages", method: "POST", body: ["user_id": userID.uuidString, "topic": topic, "body": text], authenticated: true)
    }
    func deleteMessage(_ message: ParentMessage) async throws {
        _ = try await request("/rest/v1/messages?id=eq.\(message.id.uuidString)", method: "DELETE", authenticated: true)
    }
    func report(_ message: ParentMessage) async throws {
        guard let userID else { return }
        _ = try await request("/rest/v1/reports", method: "POST", body: ["message_id": message.id.uuidString, "user_id": userID.uuidString, "reason": "Signalé depuis l’application"], authenticated: true)
    }
    func block(_ author: UUID) async throws {
        guard let userID else { return }
        _ = try await request("/rest/v1/blocks", method: "POST", body: ["user_id": userID.uuidString, "blocked_user_id": author.uuidString], authenticated: true)
    }
}
