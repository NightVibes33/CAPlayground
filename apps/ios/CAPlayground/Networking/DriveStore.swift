import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

struct DriveProject: Codable, Identifiable, Hashable {
    var id: String, name: String
    var webViewLink: String?, createdTime: String?, size: String?
}

@MainActor @Observable
final class DriveStore: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let service = "com.nightvibes33.caplayground.drive", account = "mobile-session"
    private(set) var connected = false
    private(set) var files: [DriveProject] = []
    var isLoading = false
    var error: String?
    var message: String?
    private var session: String? { didSet { connected = session != nil; save() } }
    private var webSession: ASWebAuthenticationSession?

    override init() { super.init(); session = Self.restore(); connected = session != nil }

    func connect() {
        let state = UUID().uuidString
        var parts = URLComponents(string: "https://caplayground.vercel.app/api/drive/connect")!; parts.queryItems = [.init(name: "native", value: "1"), .init(name: "state", value: state)]
        let auth = ASWebAuthenticationSession(url: parts.url!, callbackURLScheme: "caplayground") { [weak self] url, authError in
            Task { @MainActor in
                guard let self else { return }; self.isLoading = false
                if let authError { if (authError as NSError).code != ASWebAuthenticationSessionError.Code.canceledLogin.rawValue { self.error = authError.localizedDescription }; return }
                guard let url, url.host == "drive", let query = URLComponents(url: url, resolvingAgainstBaseURL: false), query.queryItems?.first(where: { $0.name == "state" })?.value == state, let value = query.queryItems?.first(where: { $0.name == "session" })?.value else { self.error = "Google Drive sign-in could not be verified."; return }
                self.session = value; await self.refresh()
            }
        }
        auth.presentationContextProvider = self; auth.prefersEphemeralWebBrowserSession = false; webSession = auth; isLoading = true; auth.start()
    }

    func disconnect() { session = nil; files = []; message = "Signed out from Google Drive." }
    func refresh() async {
        guard let session else { return }; isLoading = true; defer { isLoading = false }
        do {
            let (data, response) = try await call(method: "GET", session: session)
            updateSession(response); files = try JSONDecoder().decode(DriveFilesResponse.self, from: data).files; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func upload(_ project: CAProjectDocument) async {
        guard let session else { return }; isLoading = true; defer { isLoading = false }
        do {
            let data = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
            let (_, response) = try await call(method: "POST", session: session, body: ["action": "upload", "name": project.name, "zipData": data.base64EncodedString()]); updateSession(response); message = "\(project.name) uploaded to Google Drive."; await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func download(_ file: DriveProject, into store: ProjectStore) async {
        guard let session else { return }; isLoading = true; defer { isLoading = false }
        do {
            let (data, response) = try await call(method: "POST", session: session, body: ["action": "download", "fileId": file.id]); updateSession(response)
            let value = try JSONDecoder().decode(DriveDownloadResponse.self, from: data); guard let archive = Data(base64Encoded: value.zipData) else { throw URLError(.cannotDecodeContentData) }
            let project = try CAArchiveImporter.importProject(data: archive, suggestedName: file.name); store.update(project); message = "\(project.name) downloaded."
        } catch { self.error = error.localizedDescription }
    }
    func delete(_ file: DriveProject) async {
        guard let session else { return }; do { let (_, response) = try await call(method: "POST", session: session, body: ["action": "delete", "fileId": file.id]); updateSession(response); await refresh() } catch { self.error = error.localizedDescription }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor() }
    private func call(method: String, session: String, body: [String: String]? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://caplayground.vercel.app/api/drive/mobile")!); request.httpMethod = method; request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { let value = (try? JSONDecoder().decode(DriveError.self, from: data).error) ?? "Google Drive request failed"; throw NSError(domain: "CAPlayground.Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: value]) }; return (data, http)
    }
    private func updateSession(_ response: HTTPURLResponse) { if let value = response.value(forHTTPHeaderField: "X-Drive-Session") { session = value } }
    private func save() { Self.delete(); guard let session else { return }; SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData: Data(session.utf8)] as CFDictionary, nil) }
    private static func restore() -> String? { var result: CFTypeRef?; let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result); return status == errSecSuccess ? (result as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil }
    private static func delete() { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary) }
}

private struct DriveFilesResponse: Decodable { var files: [DriveProject] }
private struct DriveDownloadResponse: Decodable { var zipData: String }
private struct DriveError: Decodable { var error: String }
