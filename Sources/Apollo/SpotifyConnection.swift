import AppKit
import CryptoKit
import Network
import Security
import ApolloCore

/// Public client ID only; tokens live in Keychain, never in preferences or logs.
@MainActor final class SpotifyConnection: ObservableObject {
    @Published var clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published var message = "Connect to sync playlists you own or collaborate on."
    private var token: Token?
    private var login: LoopbackLogin?
    private var loginTask: Task<Void, Never>?
    static let redirect = "http://127.0.0.1:43827/callback"
    private static let service = "io.github.jkw16.apollo.spotify"

    init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: "playlist",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let saved = try? JSONDecoder().decode(Token.self, from: data), saved.clientID == clientID {
            token = saved; connected = true
        }
    }

    func connect() {
        guard !busy else { return }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.allSatisfy(\.isHexDigit) else { message = "Enter the Client ID from your Spotify developer app."; return }
        disconnect()
        clientID = id
        UserDefaults.standard.set(id, forKey: "spotifyClientID")
        busy = true; message = "Finish signing in in your browser."
        loginTask = Task {
            defer { busy = false; login = nil; loginTask = nil }
            do {
                let verifier = try Self.random()
                let state = try Self.random()
                let challenge = Self.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
                var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
                url.queryItems = ["client_id": id, "response_type": "code", "redirect_uri": Self.redirect,
                    "state": state, "scope": "user-read-currently-playing playlist-read-private playlist-read-collaborative",
                    "code_challenge_method": "S256", "code_challenge": challenge].map { URLQueryItem(name: $0.key, value: $0.value) }
                let receiver = LoopbackLogin(); login = receiver
                let code = try await receiver.code(state: state) { NSWorkspace.shared.open(url.url!) }
                try Task.checkCancellation()
                let response = try await Self.exchange(["grant_type": "authorization_code", "client_id": id,
                    "redirect_uri": Self.redirect, "code": code, "code_verifier": verifier])
                try Task.checkCancellation()
                try store(response, id: id, oldRefresh: nil)
                message = "Spotify connected. Playlist syncing is ready."
            } catch {
                message = error is CancellationError ? "Spotify sign-in cancelled." : error.localizedDescription
            }
        }
    }

    func disconnect() {
        loginTask?.cancel(); login?.cancel(); login = nil
        token = nil; connected = false
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                       kSecAttrAccount as String: "playlist"] as CFDictionary)
        message = "Spotify playlist access disconnected."
    }

    func accessToken() async throws -> String {
        guard let existing = token else { throw SpotifyWallError.signIn }
        if existing.expires > Date().addingTimeInterval(60) { return existing.access }
        let response = try await Self.exchange(["grant_type": "refresh_token", "client_id": existing.clientID,
                                                "refresh_token": existing.refresh])
        try Task.checkCancellation()
        guard token?.refresh == existing.refresh else { throw CancellationError() }
        try store(response, id: existing.clientID, oldRefresh: existing.refresh)
        return token!.access
    }

    private func store(_ response: Response, id: String, oldRefresh: String?) throws {
        guard let refresh = response.refresh_token ?? oldRefresh else { throw SpotifyWallError.signIn }
        let value = Token(clientID: id, access: response.access_token, refresh: refresh,
                          expires: Date().addingTimeInterval(response.expires_in))
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: "playlist"]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LoginError.message("Could not save Spotify access in Keychain. Please try again.") }
        token = value; connected = true
    }

    private static func exchange(_ fields: [String: String]) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.sorted { $0.key < $1.key }.map {
            $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LoginError.message("Spotify sign-in failed. Check the Client ID, redirect URL and allowed users in your developer dashboard, then reconnect.") }
        return try JSONDecoder().decode(Response.self, from: data)
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SpotifyWallError.unavailable }
        return base64(Data(bytes))
    }
    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private struct Token: Codable { let clientID: String; let access: String; let refresh: String; let expires: Date }
    private struct Response: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
}

private enum LoginError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Short-lived listener bound only to loopback. Validates the callback path
/// and OAuth state before accepting the code; never echoes tokens into HTML.
@MainActor private final class LoopbackLogin {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [NWConnection] = []
    func code(state: String, ready: @escaping () -> Void) async throws -> String {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43827)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                listener.stateUpdateHandler = { status in
                    Task { @MainActor in
                        switch status {
                        case .ready: ready()
                        case .failed: self.finish(.failure(LoginError.message("Could not open the local Spotify callback. Close another Apollo sign-in and try again.")))
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { connection in
                    Task { @MainActor in
                        guard self.connections.count < 8 else { connection.cancel(); return }
                        self.connections.append(connection)
                        connection.start(queue: .main)
                        self.receive(connection, state: state, data: Data())
                    }
                }
                listener.start(queue: .main)
                timeout = Task {
                    do { try await Task.sleep(for: .seconds(180)) }
                    catch { return }
                    finish(.failure(LoginError.message("Spotify sign-in timed out. Try Connect again.")))
                }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func receive(_ connection: NWConnection, state: String, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { bytes, _, complete, error in
            Task { @MainActor in
                var buffer = data; buffer.append(bytes ?? Data())
                guard buffer.count < 16_384, error == nil else { connection.cancel(); return }
                guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if !complete { self.receive(connection, state: state, data: buffer) }
                    else { connection.cancel() }
                    return
                }
                let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard parts.count == 3, parts[0] == "GET", let url = URLComponents(string: "http://127.0.0.1" + parts[1]),
                      url.path == "/callback", url.queryItems?.first(where: { $0.name == "state" })?.value == state else {
                    connection.cancel(); return
                }
                let code = url.queryItems?.first(where: { $0.name == "code" })?.value
                let body = "Spotify sign-in received. You can return to Apollo."
                let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in
                    Task { @MainActor in
                        if let code, !code.isEmpty { self.finish(.success(code)) }
                        else { self.finish(.failure(LoginError.message("Spotify access was not granted."))) }
                    }
                })
            }
        }
    }
    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections = []
        continuation.resume(with: result)
    }
}
