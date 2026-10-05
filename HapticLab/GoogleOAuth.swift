import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct GoogleCredential: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String
    var channelID: String = ""
    var channelTitle: String = ""
    var clientID: String
    var canWrite: Bool { scope.split(separator: " ").contains("https://www.googleapis.com/auth/youtube.force-ssl") }
}

enum MusicKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "HapticLab").youtube",
         kSecAttrAccount as String: "google-oauth"]
    }
    static func read() -> GoogleCredential? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleCredential.self, from: data)
    }
    static func save(_ credential: GoogleCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
                throw MusicError.account("ログイン情報を安全に保存できませんでした。")
            }
        } else if result != errSecSuccess { throw MusicError.account("ログイン情報を更新できませんでした。") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class GoogleOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var credential: GoogleCredential?
    private var authentication: ASWebAuthenticationSession?
    private var refreshTask: Task<GoogleCredential, Error>?
    private var generation = 0

    var clientID: String { Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? "" }
    var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") && !clientID.contains("$(") }
    private var callbackScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }

    override init() {
        super.init()
        if let saved = MusicKeychain.read(), saved.clientID == clientID { credential = saved }
    }

    func authorize(write: Bool) async throws -> GoogleCredential {
        guard isConfigured else { throw MusicError.account("Googleログインの設定が必要です。このビルドにはOAuthクライアントIDが入っていません。URL・音源ファイルとアプリ内リストは利用できます。") }
        guard authentication == nil else { throw MusicError.account("ログイン画面を操作してください。") }
        let token = generation
        let verifier = try Self.random(), state = try Self.random()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirect = "\(callbackScheme):/oauthredirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        let scope = "https://www.googleapis.com/auth/youtube.readonly" + (write ? " https://www.googleapis.com/auth/youtube.force-ssl" : "")
        components.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
            .init(name: "state", value: state), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "select_account consent")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: callbackScheme) { [weak self] url, error in
                Task { @MainActor [weak self] in
                    self?.authentication = nil
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: MusicError.account("ログインを完了できませんでした。")) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authentication = session
            if !session.start() {
                authentication = nil
                continuation.resume(throwing: MusicError.account("Googleのログイン画面を開けませんでした。"))
            }
        }
        guard token == generation, callback.scheme == callbackScheme, callback.path == "/oauthredirect",
              let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              values.first(where: { $0.name == "state" })?.value == state,
              let code = values.first(where: { $0.name == "code" })?.value else {
            throw MusicError.account("ログインがキャンセルされたか、認証の応答が一致しません。")
        }
        let response = try await tokenRequest(["client_id": clientID, "code": code, "code_verifier": verifier,
                                               "redirect_uri": redirect, "grant_type": "authorization_code"])
        guard token == generation else { throw CancellationError() }
        return GoogleCredential(accessToken: response.access_token, refreshToken: response.refresh_token ?? "",
            expiresAt: Date().addingTimeInterval(response.expires_in), scope: response.scope ?? "",
            clientID: clientID)
    }

    func save(_ value: GoogleCredential) throws {
        try MusicKeychain.save(value)
        credential = value
    }

    func accessToken() async throws -> String {
        guard let credential else { throw MusicError.account("Googleにログインしてください。") }
        if credential.expiresAt.timeIntervalSinceNow > 60 { return credential.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard !credential.refreshToken.isEmpty else { throw MusicError.account("ログインの期限が切れました。もう一度ログインしてください。") }
        let generation = self.generation
        let task = Task {
            let response = try await tokenRequest(["client_id": clientID, "refresh_token": credential.refreshToken,
                                                   "grant_type": "refresh_token"])
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            var renewed = credential
            renewed.accessToken = response.access_token
            renewed.expiresAt = Date().addingTimeInterval(response.expires_in)
            if let scope = response.scope { renewed.scope = scope }
            if let refresh = response.refresh_token { renewed.refreshToken = refresh }
            try save(renewed)
            return renewed
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    func disconnect() {
        generation += 1
        authentication?.cancel()
        authentication = nil
        refreshTask?.cancel()
        refreshTask = nil
        let token = credential?.refreshToken.isEmpty == false ? credential?.refreshToken : credential?.accessToken
        credential = nil
        MusicKeychain.clear()
        if let token {
            Task {
                var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.form(["token": token])
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let scope: String?
    }

    private func tokenRequest(_ values: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(values)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw MusicError.account("Googleの認証を更新できませんでした。接続を確認し、必要ならログインし直してください。")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !token.access_token.isEmpty, token.expires_in.isFinite, token.expires_in > 0 else {
            throw MusicError.account("Googleの認証情報が不正です。")
        }
        return token
    }

    private static func form(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw MusicError.account("認証の準備ができませんでした。") }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ value: Data) -> String {
        value.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
