import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

struct DriveProject: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var webViewLink: String?
    var createdTime: String?
    var size: String?

    var projectName: String {
        name.replacingOccurrences(of: ".ca.zip", with: "", options: [.caseInsensitive])
    }
}

@MainActor
@Observable
final class DriveStore: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let service = "com.nightvibes33.caplayground.drive"
    private static let account = "mobile-session"

    private(set) var connected = false
    private(set) var files: [DriveProject] = []
    var isLoading = false
    var error: String?
    var message: String?

    private var session: String? {
        didSet {
            connected = session != nil
            save()
        }
    }
    private var webSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        session = Self.restore()
        connected = session != nil
    }

    func connect() {
        error = nil
        message = nil
        let state = UUID().uuidString
        var parts = URLComponents(string: "https://caplayground.vercel.app/api/drive/connect")!
        parts.queryItems = [
            .init(name: "native", value: "1"),
            .init(name: "state", value: state)
        ]

        let auth = ASWebAuthenticationSession(url: parts.url!, callbackURLScheme: "caplayground") { [weak self] url, authError in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let authError {
                    if (authError as NSError).code != ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                        self.error = authError.localizedDescription
                    }
                    return
                }
                guard
                    let url,
                    url.host == "drive",
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false),
                    query.queryItems?.first(where: { $0.name == "state" })?.value == state,
                    let value = query.queryItems?.first(where: { $0.name == "session" })?.value
                else {
                    self.error = "Google Drive sign-in could not be verified."
                    return
                }
                self.session = value
                await self.refresh()
            }
        }
        auth.presentationContextProvider = self
        auth.prefersEphemeralWebBrowserSession = false
        webSession = auth
        isLoading = true
        guard auth.start() else {
            isLoading = false
            error = "Unable to start Google Drive sign-in."
            return
        }
    }

    func disconnect() {
        session = nil
        files = []
        message = "Signed out from Google Drive successfully."
        error = nil
    }

    func refresh() async {
        guard let session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await call(method: "GET", session: session)
            updateSession(response)
            files = try JSONDecoder().decode(DriveFilesResponse.self, from: data).files
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func upload(_ project: CAProjectDocument, replacing fileID: String? = nil) async -> DriveProject? {
        guard let session else {
            error = "Google Drive is not connected."
            return nil
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
            var body = [
                "action": "upload",
                "name": project.name,
                "zipData": archive.base64EncodedString()
            ]
            if let fileID { body["fileId"] = fileID }
            let (data, response) = try await call(method: "POST", session: session, body: body)
            updateSession(response)
            let value = try JSONDecoder().decode(DriveUploadResponse.self, from: data)
            message = value.updated == true ? "\(project.name) updated in Google Drive." : "\(project.name) uploaded to Google Drive."
            await refresh()
            return value.file
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func sync(_ project: CAProjectDocument) async -> DriveProject? {
        if files.isEmpty { await refresh() }
        let existing = files.first { $0.projectName.caseInsensitiveCompare(project.name) == .orderedSame }
        return await upload(project, replacing: existing?.id)
    }

    @discardableResult
    func download(_ file: DriveProject, into store: ProjectStore) async -> CAProjectDocument? {
        guard let session else {
            error = "Google Drive is not connected."
            return nil
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await call(
                method: "POST",
                session: session,
                body: ["action": "download", "fileId": file.id]
            )
            updateSession(response)
            let value = try JSONDecoder().decode(DriveDownloadResponse.self, from: data)
            guard let archive = Data(base64Encoded: value.zipData) else { throw URLError(.cannotDecodeContentData) }
            let project = try CAArchiveImporter.importProject(data: archive, suggestedName: file.projectName)
            store.update(project)
            message = "\(project.name) downloaded."
            return project
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func delete(_ file: DriveProject) async {
        guard let session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (_, response) = try await call(
                method: "POST",
                session: session,
                body: ["action": "delete", "fileId": file.id]
            )
            updateSession(response)
            files.removeAll { $0.id == file.id }
            message = "Deleted \(file.projectName) from Google Drive."
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAll() async -> Bool {
        guard let session else {
            error = "Google Drive is not connected."
            return false
        }
        isLoading = true
        message = nil
        error = nil
        defer { isLoading = false }
        do {
            let (_, response) = try await call(
                method: "POST",
                session: session,
                body: ["action": "deleteAll"]
            )
            updateSession(response)
            files = []
            message = "All cloud projects have been deleted successfully."
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func call(
        method: String,
        session: String,
        body: [String: String]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://caplayground.vercel.app/api/drive/mobile")!)
        request.httpMethod = method
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let value = (try? JSONDecoder().decode(DriveError.self, from: data).error) ?? "Google Drive request failed"
            throw NSError(domain: "CAPlayground.Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: value])
        }
        return (data, http)
    }

    private func updateSession(_ response: HTTPURLResponse) {
        if let value = response.value(forHTTPHeaderField: "X-Drive-Session") { session = value }
    }

    private func save() {
        Self.deleteSession()
        guard let session else { return }
        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: Data(session.utf8)
        ] as CFDictionary, nil)
    }

    private static func restore() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        return status == errSecSuccess ? (result as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
    }

    private static func deleteSession() {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary)
    }
}

private struct DriveFilesResponse: Decodable { var files: [DriveProject] }
private struct DriveDownloadResponse: Decodable { var zipData: String }
private struct DriveUploadResponse: Decodable { var success: Bool; var file: DriveProject; var updated: Bool? }
private struct DriveError: Decodable { var error: String }
