import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case badResponse
    case server(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有配置服务器"
        case .unauthorized: return "访问令牌无效，请在设置里更新"
        case .badResponse: return "服务器返回了无法识别的数据"
        case .server(let m): return m
        case .transport(let m): return m
        }
    }
}

struct APIClient {
    let base: URL
    let token: String

    init(base: URL, token: String) {
        self.base = base
        self.token = token
    }

    private func makeURL(_ path: String, _ query: [String: String]) throws -> URL {
        guard var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badResponse
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.badResponse }
        return url
    }

    private func send(_ path: String, query: [String: String] = [:], method: String = "GET", body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: try makeURL(path, query))
        req.httpMethod = method
        req.timeoutInterval = 25
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
            switch http.statusCode {
            case 200...299: return data
            case 401: throw APIError.unauthorized
            default:
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = obj["error"] as? String {
                    throw APIError.server(msg)
                }
                throw APIError.server("请求失败（HTTP \(http.statusCode)）")
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        let data = try await send(path, query: query)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.badResponse }
    }

    func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        let out = try await send(path, method: "POST", body: data)
        do { return try decoder.decode(T.self, from: out) }
        catch { throw APIError.badResponse }
    }

    func health() async throws -> Health {
        let data = try await send("/api/v1/health")
        return try decoder.decode(Health.self, from: data)
    }

    func rawFile(path: String) async throws -> Data {
        try await send("/api/v1/files/raw", query: ["path": path])
    }

    func assetsBase(report: String) -> URL {
        base.appendingPathComponent("api/v1/report-assets/reports")
    }

    func memory(path: String) async throws -> MemoryListing {
        try await get("/api/v1/memory", ["path": path])
    }

    func memoryFile(path: String) async throws -> MemoryFile {
        try await get("/api/v1/memory/file", ["path": path])
    }

    func repoStats() async throws -> RepoStats {
        try await get("/api/v1/repo")
    }

    func upload(dir: String, name: String, data: Data) async throws {
        let url = try makeURL("/api/v1/files/upload", ["path": dir, "name": name])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let (_, resp) = try await URLSession.shared.upload(for: req, from: data)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("上传失败")
        }
    }
}

struct TokenResult: Codable { var ok: Bool; var token: String? }
