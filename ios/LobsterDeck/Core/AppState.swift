import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    private let urlKey = "server.url"
    private let tokenKey = "api.token"

    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: urlKey) }
    }
    var token: String {
        didSet { Keychain.set(token, for: tokenKey) }
    }

    var overview: Overview?
    var reports: [Report] = []
    var agents: [AgentInfo] = []
    var recentFiles: [FileEntry] = []
    var repoStats: RepoStats?

    var isLoading = false
    var lastError: String?
    var lastRefresh: Date?
    var healthVersion: String?

    init() {
        serverURL = UserDefaults.standard.string(forKey: urlKey) ?? "https://deck.liguiyu.com:10443"
        token = Keychain.get(tokenKey) ?? ""
    }

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !token.isEmpty
    }

    func client() throws -> APIClient {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { throw APIError.notConfigured }
        guard !token.isEmpty else { throw APIError.notConfigured }
        return APIClient(base: url, token: token)
    }

    func testConnection() async -> String? {
        do {
            let h = try await client().health()
            healthVersion = h.version
            return nil
        } catch {
            return error.localizedDescription
        }
    }


    /// Cancellation is a normal lifecycle event, never a user-facing error.
    private func visibleError(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return nil }
        return error.localizedDescription
    }

    func refreshAll() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try client()
            async let ov: Overview = api.get("/api/v1/overview")
            async let rp: ReportList = api.get("/api/v1/reports")
            async let ag: AgentList = api.get("/api/v1/agents")
            async let fl: RecentFiles = api.get("/api/v1/files/recent", ["limit": "8"])
            async let rs: RepoStats = api.get("/api/v1/repo")
            let (o, r, a, f, repo) = try await (ov, rp, ag, fl, rs)
            overview = o
            reports = r.items
            agents = a.items
            recentFiles = f.items
            repoStats = repo
            lastRefresh = Date()
            lastError = nil
        } catch {
            lastError = visibleError(error)
        }
    }

    func refreshReports() async {
        guard isConfigured else { return }
        do {
            let r: ReportList = try await client().get("/api/v1/reports")
            reports = r.items
        } catch { lastError = visibleError(error) }
    }

    func refreshAgents() async {
        guard isConfigured else { return }
        do {
            let a: AgentList = try await client().get("/api/v1/agents")
            agents = a.items
        } catch { lastError = visibleError(error) }
    }

    func share(_ file: String, action: String) async throws -> String? {
        let res: TokenResult = try await client().post("/api/v1/reports/tokens",
                                                       body: ["file": file, "action": action])
        await refreshReports()
        return res.token
    }
}

enum Route: Hashable {
    case report(String)
    case folder(String)
    case file(String)
    case agent(String)
    case commit(String)
    case memory(String)
    case memoryFile(String)
}
