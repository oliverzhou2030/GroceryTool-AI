#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Network
import Security

@MainActor
final class GoogleSheetsService {
    static let shared = GoogleSheetsService()

    private let clientID: String
    private let clientSecret: String

    private init() {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["GOOGLE_OAUTH_CREDENTIALS_FILE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let credentials = try? JSONDecoder().decode(OAuthClientFile.self, from: data) {
            clientID = credentials.installed.clientID
            clientSecret = credentials.installed.clientSecret
        } else {
            clientID = ""
            clientSecret = ""
        }
    }

    func createSpreadsheet(title: String, rows: [[String]]) async throws -> URL {
        guard !clientID.isEmpty, !clientSecret.isEmpty else { throw GoogleSheetsError.notConfigured }
        let accessToken = try await accessToken()
        let createBody: [String: Any] = ["properties": ["title": title]]
        let createData = try await googleRequest(
            url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!,
            method: "POST",
            accessToken: accessToken,
            json: createBody
        )
        let created = try JSONDecoder().decode(CreatedSpreadsheet.self, from: createData)
        guard !created.spreadsheetId.isEmpty else { throw GoogleSheetsError.invalidResponse }

        let range = "A1".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "A1"
        let valuesURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(created.spreadsheetId)/values/\(range)?valueInputOption=RAW")!
        _ = try await googleRequest(
            url: valuesURL,
            method: "PUT",
            accessToken: accessToken,
            json: ["majorDimension": "ROWS", "values": rows]
        )
        let formattingURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(created.spreadsheetId):batchUpdate")!
        _ = try await googleRequest(
            url: formattingURL,
            method: "POST",
            accessToken: accessToken,
            json: ["requests": [
                ["repeatCell": [
                    "range": ["sheetId": 0],
                    "cell": ["userEnteredFormat": ["wrapStrategy": "WRAP"]],
                    "fields": "userEnteredFormat.wrapStrategy"
                ]],
                ["autoResizeDimensions": [
                    "dimensions": ["sheetId": 0, "dimension": "COLUMNS", "startIndex": 0, "endIndex": 8]
                ]],
                ["autoResizeDimensions": [
                    "dimensions": ["sheetId": 0, "dimension": "ROWS", "startIndex": 0, "endIndex": max(rows.count, 1)]
                ]]
            ]]
        )
        guard let url = URL(string: created.spreadsheetUrl) else { throw GoogleSheetsError.invalidResponse }
        return url
    }

    private func accessToken() async throws -> String {
        if let refreshToken = OAuthKeychain.refreshToken {
            do { return try await refreshAccessToken(refreshToken) } catch { OAuthKeychain.refreshToken = nil }
        }
        return try await authorize()
    }

    private func authorize() async throws -> String {
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafeString(byteCount: 24)
        let callback = try LocalOAuthCallback()
        let redirectURI = try await callback.start()
        let callbackTask = Task { try await callback.authorizationCode(expectedState: state) }

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authorizationURL = components.url else { throw GoogleSheetsError.invalidResponse }
        NSWorkspace.shared.open(authorizationURL)
        let code = try await callbackTask.value
        let token = try await tokenRequest([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString
        ])
        if let refreshToken = token.refreshToken { OAuthKeychain.refreshToken = refreshToken }
        return token.accessToken
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        let token = try await tokenRequest([
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        return token.accessToken
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private func googleRequest(url: URL, method: String, accessToken: String, json: Any) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return data
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw GoogleSheetsError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?
                .flatMap { $0["message"] as? String }
            throw GoogleSheetsError.server(detail ?? "Google returned HTTP \(response.statusCode).")
        }
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private struct CreatedSpreadsheet: Decodable {
    let spreadsheetId: String
    let spreadsheetUrl: String
}

private struct OAuthClientFile: Decodable {
    let installed: Installed

    struct Installed: Decodable {
        let clientID: String
        let clientSecret: String

        private enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
        }
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private enum GoogleSheetsError: LocalizedError {
    case notConfigured
    case invalidResponse
    case callback(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Sheets is not configured. Start the app with ./run-mac.command."
        case .invalidResponse: "Google returned an invalid response."
        case .callback(let message), .server(let message): message
        }
    }
}

private final class LocalOAuthCallback: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "GroceryToolAI.GoogleOAuthCallback")
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var expectedState = ""

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = self.listener.port {
                    self.readyContinuation?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/oauth2callback")!)
                    self.readyContinuation = nil
                }
            case .failed(let error):
                self.readyContinuation?.resume(throwing: error)
                self.readyContinuation = nil
                self.codeContinuation?.resume(throwing: error)
                self.codeContinuation = nil
            default: break
            }
        }
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.start(queue: queue)
        }
    }

    func authorizationCode(expectedState: String) async throws -> String {
        self.expectedState = expectedState
        return try await withCheckedThrowingContinuation { codeContinuation = $0 }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_535) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.finish(.failure(error), connection: connection); return }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first,
                  let path = firstLine.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://127.0.0.1\(path)") else {
                self.finish(.failure(GoogleSheetsError.callback("Google sign-in returned an invalid callback.")), connection: connection)
                return
            }
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = values["error"] {
                self.finish(.failure(GoogleSheetsError.callback("Google sign-in was not completed: \(error).")), connection: connection)
            } else if values["state"] != self.expectedState {
                self.finish(.failure(GoogleSheetsError.callback("Google sign-in security validation failed.")), connection: connection)
            } else if let code = values["code"], !code.isEmpty {
                self.finish(.success(code), connection: connection)
            } else {
                self.finish(.failure(GoogleSheetsError.callback("Google sign-in did not return an authorization code.")), connection: connection)
            }
        }
    }

    private func finish(_ result: Result<String, Error>, connection: NWConnection) {
        let succeeded = (try? result.get()) != nil
        let title = succeeded ? "Google Sheets connected" : "Google Sheets connection failed"
        let body = "<html><body style='font-family:-apple-system;padding:40px'><h1>\(title)</h1><p>You can return to GroceryTool AI.</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        codeContinuation?.resume(with: result)
        codeContinuation = nil
        listener.cancel()
    }
}

private enum OAuthKeychain {
    private static let service = "com.oliverzhou2030.GroceryToolAI.GoogleSheets"
    private static let account = "refresh-token"

    static var refreshToken: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? self
    }
}
#endif
