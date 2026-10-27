import Foundation
import Security

struct CloudFailure: Error {
    let code: String
    var key: String { "cloud." + code }
}
struct CloudAck: Codable { let ok: Bool }
struct CloudSession: Codable { let account: CafeAccount; let credential: String }
struct CloudCredential: Codable { let credential: String }
struct CloudCatalog: Codable { let products: [Product] }
struct CloudState: Codable { var favorites: Set<String>; var cart: [CartLine]; var revision: Int }
struct CloudOrders: Codable { let orders: [Order] }
struct CloudOrderRequest: Codable {
    let requestKey: UUID
    let customer: String
    let note: String
    let expectedTotal: Int
    let lines: [CartLine]
    let revision: Int
    var promotionCode: String? = nil
    var fulfillment: String? = nil
    var addressID: UUID? = nil
}

@MainActor final class APIClient {
    static let shared = APIClient()
    static let baseURL = URL(string: "https://br-long-fog-ba7moks4-cookiecup.compute.c-8.eu-central-1.aws.neon.tech/v1/")!
    private let session: URLSession
    private var credential: String?
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
        credential = try? SessionKeychain.read()
    }
    private(set) var supportsPlatform = false
    private var healthTime = Date.distantPast
    private var healthTask: Task<Void, Never>?
    func checkPlatform() async {
        if let task = healthTask { await task.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.fetchPlatform()
        }
        healthTask = task
        await task.value
        healthTask = nil
    }
    private func fetchPlatform() async {
        guard Date().timeIntervalSince(healthTime) > 30 else { return }
        struct Health: Decodable { let version: Int? }
        do {
            let health: Health = try await request("health", method: "GET", data: nil, version: "")
            supportsPlatform = (health.version ?? 1) >= 2; healthTime = Date()
        } catch { /* Preserve the last known server capabilities during temporary outages. */ }
    }
    var hasCredential: Bool { credential != nil }
    func saveCredential(_ value: String) throws { try SessionKeychain.write(value); credential = value }
    func clearCredential() throws { try SessionKeychain.delete(); credential = nil }
    func get<T: Decodable>(_ path: String) async throws -> T { try await request(path, method: "GET", data: nil) }
    func send<Body: Encodable, Result: Decodable>(_ path: String, method: String = "POST", body: Body) async throws -> Result {
        try await request(path, method: method, data: JSONEncoder().encode(body))
    }
    func getV2<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(path, method: "GET", data: nil, version: "v2", query: query)
    }
    func sendV2<Body: Encodable, Result: Decodable>(_ path: String, method: String = "POST", body: Body) async throws -> Result {
        try await request(path, method: method, data: JSONEncoder().encode(body), version: "v2")
    }
    static var origin: URL { baseURL.deletingLastPathComponent() }
    private func request<T: Decodable>(_ path: String, method: String, data: Data?, version: String = "v1", query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: Self.origin.appendingPathComponent(version).appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credential = credential { request.setValue(credential, forHTTPHeaderField: "X-CookieCup-Session") }
        let (bytes, response): (Data, URLResponse)
        do { (bytes, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { if Task.isCancelled { throw CancellationError() }; throw CloudFailure(code: "network") }
        guard let response = response as? HTTPURLResponse else { throw CloudFailure(code: "server") }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            throw CloudFailure(code: error?["error"] as? String ?? "server")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer(); let string = try container.decode(String.self)
            let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = format.date(from: string) { return date }
            format.formatOptions = [.withInternetDateTime]
            guard let date = format.date(from: string) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date") }
            return date
        }
        do { return try decoder.decode(T.self, from: bytes) }
        catch { throw CloudFailure(code: "server") }
    }
}
private enum SessionKeychain {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "CookieCup") + ".remoteSession.v1",
        kSecAttrAccount as String: "session"] }
    static func read() throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw AccountFailure.storage }
        return value
    }
    static func write(_ value: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query; attributes.forEach { insertion[$0.key] = $0.value }; status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccountFailure.storage }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountFailure.storage }
    }
}
