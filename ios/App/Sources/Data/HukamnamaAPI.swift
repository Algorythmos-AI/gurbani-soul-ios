import Foundation

// THE ONLY FILE IN THE APP THAT TALKS TO A SERVER (ios/tests gate `test_no_network_code` allows
// this file and no other). It reaches the Hukamnama service, and only while the reader has turned
// the feature on or opens its card/sheet:
//   PUT    /v1/devices/<token>         {env, mode, schedule?, scripture_sha256, replaces?}
//   DELETE /v1/devices/<token>
//   GET    /v1/hukamnama/today · /v1/hukamnama/<yyyy-MM-dd>
// No account, no cookies, no cache, no identifiers beyond the APNs token in the path.

/// The HTTP client for `HukamnamaServing` (the protocol and its fake live in HukamnamaPush.swift).
struct HukamnamaHTTPService: HukamnamaServing {
    let base: URL

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private func request(_ path: String, method: String, body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func send(_ r: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await Self.session.data(for: r)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw HukamnamaServiceError.offline
        }
    }

    func register(token: String, body: HukamnamaDeviceBody) async throws {
        guard HukamnamaDeviceBody.isValidToken(token) else { throw HukamnamaServiceError.malformed }
        let data = try HukamnamaDeviceBody.encoder.encode(body)
        let (_, status) = try await send(request("v1/devices/\(token)", method: "PUT", body: data))
        guard (200..<300).contains(status) else { throw HukamnamaServiceError.rejected(status) }
    }

    func unregister(token: String) async throws {
        guard HukamnamaDeviceBody.isValidToken(token) else { return }
        let (_, status) = try await send(request("v1/devices/\(token)", method: "DELETE"))
        // 404: the row is already gone — exactly what a delete wants
        guard (200..<300).contains(status) || status == 404 else { throw HukamnamaServiceError.rejected(status) }
    }

    func fetch(date: String?) async throws -> HukamnamaEntry? {
        if let date, !AmritsarDate.isValidKey(date) { throw HukamnamaServiceError.malformed }
        let (data, status) = try await send(request("v1/hukamnama/\(date ?? "today")", method: "GET"))
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw HukamnamaServiceError.rejected(status) }
        guard let entry = try? HukamnamaStore.decoder.decode(HukamnamaEntry.self, from: data),
              AmritsarDate.isValidKey(entry.amritsarDate) else { throw HukamnamaServiceError.malformed }
        return entry
    }
}
