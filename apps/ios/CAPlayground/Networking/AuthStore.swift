import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

struct AuthUser: Codable, Hashable {
    struct Identity: Codable, Hashable, Identifiable {
        var id: String
        var provider: String
        var identityData: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case id, provider
            case identityData = "identity_data"
        }

        var email: String? {
            guard case .string(let value) = identityData?["email"] else { return nil }
            return value
        }
    }

    var id: String
    var email: String?
    var userMetadata: [String: JSONValue]? = nil
    var appMetadata: [String: JSONValue]? = nil
    var identities: [Identity]? = nil

    enum CodingKeys: String, CodingKey {
        case id, email, identities
        case userMetadata = "user_metadata"
        case appMetadata = "app_metadata"
    }
}

struct WallpaperSubmission: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var description: String
    var status: String
    var submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description, status
        case submittedAt = "submitted_at"
    }
}

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }
}

private struct AuthResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Double
    var user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct APIErrorBody: Decodable {
    var msg: String?
    var message: String?
    var errorDescription: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case msg, message, error
        case errorDescription = "error_description"
    }
}

@MainActor
@Observable
final class AuthStore: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let supabaseURL = URL(string: "https://thhijbwnlphprlqpbepg.supabase.co")!
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRoaGlqYndubHBocHJscXBiZXBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4OTYwNTEsImV4cCI6MjA4ODI1NjA1MX0.jGah76lXc8VkZXjlLZ0f9fZp3fhGjjyJlzmphWonwmw"
    private static let keychainService = "com.nightvibes33.caplayground.auth"
    private static let keychainAccount = "supabase-session"

    private(set) var user: AuthUser?
    private(set) var username = ""
    var isLoading = false
    var message: String?
    var error: String?
    var requiresPasswordReset = false

    private var session: AuthSession?
    private var webAuthenticationSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        restoreSession()
        if session != nil {
            Task { await refreshUser() }
        }
    }

    var isSignedIn: Bool { user != nil }

    func signIn(email: String, password: String) async -> Bool {
        await performAuth(path: "/auth/v1/token?grant_type=password", body: ["email": email, "password": password])
    }

    func signUp(username: String, email: String, password: String) async -> Bool {
        guard username.range(of: "^[A-Za-z0-9!._-]{3,20}$", options: .regularExpression) != nil else {
            error = "Username must be 3-20 chars and only letters, numbers, and ! - _ ."
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let body: [String: Any] = ["email": email, "password": password, "data": ["username": username]]
            let (_, response) = try await request(path: "/auth/v1/signup", method: "POST", body: body)
            guard (200..<300).contains(response.statusCode) else { throw lastResponseError }
            message = "Check your email for a confirmation link."
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func signIn(provider: String) {
        error = nil
        var components = URLComponents(url: Self.supabaseURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: "caplayground://auth/callback")
        ]
        guard let url = components.url else { return }
        let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "caplayground") { [weak self] callbackURL, authError in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let authError {
                    if (authError as NSError).code != ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                        self.error = authError.localizedDescription
                    }
                    return
                }
                guard let callbackURL else { return }
                await self.acceptOAuthCallback(callbackURL)
            }
        }
        auth.presentationContextProvider = self
        auth.prefersEphemeralWebBrowserSession = false
        webAuthenticationSession = auth
        isLoading = true
        auth.start()
    }

    func refreshUser() async {
        guard await ensureValidSession(), let token = session?.accessToken else { return }
        do {
            let (data, response) = try await request(path: "/auth/v1/user", token: token)
            guard response.statusCode == 200 else { throw lastResponseError }
            let value = try JSONDecoder().decode(AuthUser.self, from: data)
            user = value
            session?.user = value
            saveSession()
            await loadUsername()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveUsername(_ value: String) async {
        guard let id = user?.id, let token = await validAccessToken() else { return }
        do {
            let body: [String: Any] = ["id": id, "username": value]
            let (_, response) = try await request(
                path: "/rest/v1/profiles", method: "POST", body: body, token: token,
                additionalHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
            )
            guard (200..<300).contains(response.statusCode) else { throw lastResponseError }
            username = value
            message = "Username saved"
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func updateEmail(_ value: String) async -> Bool {
        guard let token = await validAccessToken() else { return false }
        do {
            let (_, response) = try await request(path: "/auth/v1/user", method: "PUT", body: ["email": value], token: token)
            guard (200..<300).contains(response.statusCode) else { throw lastResponseError }
            message = "Verification email sent to update your email. You'll be signed out now; please sign back in after verifying."
            await signOut()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func sendPasswordReset(email: String) async {
        do {
            let body = ["email": email, "redirect_to": "caplayground://auth/reset-password"]
            let (_, response) = try await request(path: "/auth/v1/recover", method: "POST", body: body)
            guard (200..<300).contains(response.statusCode) else { throw lastResponseError }
            message = "If the email exists, a reset link has been sent."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme == "caplayground" else { return }
        await acceptOAuthCallback(url)
    }

    func updatePassword(_ password: String) async -> Bool {
        guard password.count >= 6, let token = await validAccessToken() else {
            error = "Password must be at least 6 characters."
            return false
        }
        do {
            let (_, response) = try await request(path: "/auth/v1/user", method: "PUT", body: ["password": password], token: token)
            guard (200..<300).contains(response.statusCode) else { throw lastResponseError }
            requiresPasswordReset = false
            message = "Password updated successfully."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func wallpaperSubmissions() async -> [WallpaperSubmission] {
        guard let id = user?.id, let token = await validAccessToken() else { return [] }
        do {
            let formatter = ISO8601DateFormatter()
            let (data, response) = try await request(path: "/rest/v1/wallpaper_submissions?user_id=eq.\(id)&select=id,name,description,status,submitted_at&order=submitted_at.desc", token: token)
            guard response.statusCode == 200 else { throw lastResponseError }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer(), value = try container.decode(String.self)
                let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: value) ?? fractional.date(from: value) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date") }
                return date
            }
            return try decoder.decode([WallpaperSubmission].self, from: data)
        } catch { self.error = error.localizedDescription; return [] }
    }

    func submitWallpaper(name: String, description: String, tendies: Data, video: Data, videoExtension: String) async -> URL? {
        guard let token = await validAccessToken() else { error = "You must be signed in to submit."; return nil }
        do {
            var request = URLRequest(url: URL(string: "https://caplayground.vercel.app/api/wallpapers/submit")!)
            request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "description": description, "username": username.isEmpty ? "Anonymous" : username, "tendiesBase64": tendies.base64EncodedString(), "videoBase64": video.base64EncodedString(), "videoExtension": videoExtension])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let api = try? JSONDecoder().decode(APIErrorBody.self, from: data); throw NSError(domain: "CAPlayground.Submission", code: 1, userInfo: [NSLocalizedDescriptionKey: api?.error ?? "Failed to submit wallpaper"])
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (object?["pullRequestURL"] as? String).flatMap(URL.init(string:))
        } catch { self.error = error.localizedDescription; return nil }
    }

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await request(path: "/auth/v1/logout", method: "POST", token: token)
        }
        session = nil
        user = nil
        username = ""
        deleteSession()
    }

    func deleteAccount() async -> Bool {
        guard let token = await validAccessToken(),
              let url = URL(string: "https://caplayground.vercel.app/api/account/delete") else { return false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let api = try? JSONDecoder().decode(APIErrorBody.self, from: data)
                throw NSError(domain: "CAPlayground.Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: api?.error ?? "Failed to delete account"])
            }
            session = nil
            user = nil
            username = ""
            deleteSession()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private var lastResponseError = NSError(domain: "CAPlayground.Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Authentication request failed"])

    private func performAuth(path: String, body: [String: Any]) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await request(path: path, method: "POST", body: body)
            guard (200..<300).contains(response.statusCode) else { throw lastResponseError }
            let value = try JSONDecoder().decode(AuthResponse.self, from: data)
            install(value)
            await loadUsername()
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func acceptOAuthCallback(_ url: URL) async {
        let fragment = URLComponents(string: "?" + (url.fragment ?? ""))?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: fragment.map { ($0.name, $0.value ?? "") })
        guard let access = values["access_token"], let refresh = values["refresh_token"] else {
            error = values["error_description"] ?? "Sign-in failed or expired"
            return
        }
        let expires = Double(values["expires_in"] ?? "3600") ?? 3600
        session = AuthSession(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires), user: AuthUser(id: "", email: nil))
        saveSession()
        await refreshUser()
        requiresPasswordReset = values["type"] == "recovery" || url.host == "reset-password"
    }

    private func ensureValidSession() async -> Bool {
        guard let current = session else { return false }
        if current.expiresAt.timeIntervalSinceNow > 60 { return true }
        return await refreshSession()
    }

    private func validAccessToken() async -> String? {
        guard await ensureValidSession() else { return nil }
        return session?.accessToken
    }

    private func refreshSession() async -> Bool {
        guard let refresh = session?.refreshToken else { return false }
        return await performAuth(path: "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh])
    }

    private func install(_ value: AuthResponse) {
        session = AuthSession(accessToken: value.accessToken, refreshToken: value.refreshToken, expiresAt: .now.addingTimeInterval(value.expiresIn), user: value.user)
        user = value.user
        saveSession()
    }

    private func loadUsername() async {
        guard let id = user?.id, !id.isEmpty, let token = await validAccessToken() else { return }
        do {
            let path = "/rest/v1/profiles?id=eq.\(id)&select=username"
            let (data, response) = try await request(path: path, token: token)
            guard response.statusCode == 200 else { return }
            let rows = try JSONDecoder().decode([[String: String?]].self, from: data)
            username = rows.first.flatMap { $0["username"] ?? nil } ?? ""
        } catch { }
    }

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil, token: String? = nil, additionalHeaders: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: Self.supabaseURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (key, value) in additionalHeaders { request.setValue(value, forHTTPHeaderField: key) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if !(200..<300).contains(http.statusCode) {
            let api = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let text = api?.msg ?? api?.message ?? api?.errorDescription ?? api?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            lastResponseError = NSError(domain: "CAPlayground.Auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        return (data, http)
    }

    private func saveSession() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        deleteSession()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func restoreSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let restored = try? JSONDecoder().decode(AuthSession.self, from: data) else { return }
        session = restored
        user = restored.user.id.isEmpty ? nil : restored.user
    }

    private func deleteSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
