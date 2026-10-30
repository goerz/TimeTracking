// APNsClient: WidgetKit pushes over HTTP/2 to the APNs sandbox
// (spec_architecture.md §2.4).

public import Foundation

/// The HTTP layer of the push client; `URLSession` in the app, a recorder in tests.
public protocol HTTPSending: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPSending {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PushError.network("Not an HTTP response.")
        }
        return (data, http)
    }
}

/// The answer of APNs to one push.
public struct APNsResponse: Sendable, Hashable {
    public var status: Int
    /// The `reason` of an error body, e.g. `BadDeviceToken`.
    public var reason: String?

    public init(status: Int, reason: String? = nil) {
        self.status = status
        self.reason = reason
    }

    public var isSuccess: Bool {
        status == 200
    }
}

/// Sends a WidgetKit push to one device token.
public protocol WidgetPushing: Sendable {
    /// Whether an auth key is installed.
    func hasKey() async -> Bool
    /// Sends `{"aps":{"content-changed":true}}` to `token`.
    func pushWidgets(to token: String) async throws(PushError) -> APNsResponse
}

/// The push client: reads the key, signs the provider token, and sends
/// `POST https://api.sandbox.push.apple.com/3/device/<token>`.
public actor APNsClient: WidgetPushing {
    public static let host = URL(string: "https://api.sandbox.push.apple.com")
    public static let body = Data(#"{"aps":{"content-changed":true}}"#.utf8)

    private let source: any APNsCredentialSource
    /// `<APP_ID>.push-type.widgets`.
    public let topic: String
    private let clock: any Clock
    private let http: any HTTPSending
    private var signer: APNsTokenSigner?

    public init(credentials: any APNsCredentialSource, topic: String, clock: any Clock, http: any HTTPSending = URLSession.shared) {
        self.source = credentials
        self.topic = topic
        self.clock = clock
        self.http = http
    }

    public func hasKey() -> Bool {
        (try? loadSigner()) != nil
    }

    /// The request for `token`, signed at the clock's time.
    public func request(for token: String) throws(PushError) -> URLRequest {
        guard var signer = try loadSigner() else {
            throw .noKey
        }
        let jwt = try signer.token(at: clock.now)
        self.signer = signer
        guard let url = Self.host?.appending(path: "3/device/\(token)") else {
            throw .network("Invalid device token.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("widgets", forHTTPHeaderField: "apns-push-type")
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = Self.body
        return request
    }

    public func pushWidgets(to token: String) async throws(PushError) -> APNsResponse {
        let request = try request(for: token)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch {
            throw .network(error.localizedDescription)
        }
        let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
        if response.statusCode == 403, reason == "ExpiredProviderToken" {
            signer = nil
        }
        return APNsResponse(status: response.statusCode, reason: reason)
    }

    /// The signer, loading the key on first use (and again while none is installed).
    private func loadSigner() throws(PushError) -> APNsTokenSigner? {
        if let signer {
            return signer
        }
        guard let credentials = try source.credentials() else {
            return nil
        }
        let loaded = try APNsTokenSigner(credentials: credentials)
        signer = loaded
        return loaded
    }
}
