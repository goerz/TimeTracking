// The APNs request and its provider token (spec_architecture.md §2.4, §8 item 11).

import CryptoKit
import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// Records every request and answers with a fixed status.
final class RecordingHTTP: HTTPSending {
    private let log = Mutex<[URLRequest]>([])
    let status: Int

    init(status: Int = 200) {
        self.status = status
    }

    var requests: [URLRequest] {
        log.withLock { $0 }
    }

    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        let url = request.url ?? URL(filePath: "/")
        let body = status == 200 ? Data() : Data(#"{"reason":"BadDeviceToken"}"#.utf8)
        return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil) ?? HTTPURLResponse())
    }
}

struct APNsClientTests {
    @Test("ARCH-11 the push request, its ES256 JWT, and reuse for 49 but not 51 minutes")
    func requestAndToken() async throws {
        let key = P256.Signing.PrivateKey()
        let credentials = APNsCredentials(keyID: "ABC123DEFG", teamID: "T", privateKeyPEM: key.pemRepresentation)
        let clock = ManualClock.fixture()
        let http = RecordingHTTP()
        let client = APNsClient(credentials: StaticAPNsCredentials(credentials), topic: "X.push-type.widgets", clock: clock, http: http)
        let response = try await client.pushWidgets(to: "abcd")
        #expect(response == APNsResponse(status: 200))

        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.sandbox.push.apple.com/3/device/abcd")
        #expect(request.value(forHTTPHeaderField: "apns-push-type") == "widgets")
        #expect(request.value(forHTTPHeaderField: "apns-topic") == "X.push-type.widgets")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String: Bool]])
        #expect(json == ["aps": ["content-changed": true]])

        let jwt = try Self.jwt(of: request)
        let parts = jwt.split(separator: ".").map(String.init)
        try #require(parts.count == 3)
        let header = try #require(try JSONSerialization.jsonObject(with: Self.decode(parts[0])) as? [String: String])
        #expect(header == ["alg": "ES256", "kid": "ABC123DEFG"])
        let claims = try #require(try JSONSerialization.jsonObject(with: Self.decode(parts[1])) as? [String: Any])
        #expect(claims["iss"] as? String == "T")
        #expect(claims["iat"] as? Int == Int(clock.now.timeIntervalSince1970))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: Self.decode(parts[2]))
        #expect(key.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))

        clock.advance(by: 49 * 60)
        _ = try await client.pushWidgets(to: "abcd")
        #expect(try Self.jwt(of: http.requests[1]) == jwt)
        clock.advance(by: 2 * 60)
        _ = try await client.pushWidgets(to: "abcd")
        let renewed = try Self.jwt(of: http.requests[2])
        #expect(renewed != jwt)
        let renewedClaims = try JSONSerialization.jsonObject(with: Self.decode(String(renewed.split(separator: ".")[1])))
        #expect((renewedClaims as? [String: Any])?["iat"] as? Int == Int(clock.now.timeIntervalSince1970))
    }

    @Test("ARCH-11 without the Keychain item the client reports that no key is installed")
    func noKey() async throws {
        let http = RecordingHTTP()
        let client = APNsClient(
            credentials: StaticAPNsCredentials(nil),
            topic: "X.push-type.widgets",
            clock: ManualClock.fixture(),
            http: http
        )
        #expect(await client.hasKey() == false)
        await #expect(throws: PushError.noKey) {
            try await client.pushWidgets(to: "abcd")
        }
        #expect(http.requests.isEmpty)
        #expect(throws: PushError.self) {
            try APNsCredentials(secret: Data("not json".utf8))
        }
        let secret = Data(#"{"keyID": "ABC123DEFG", "teamID": "T", "p8": "pem"}"#.utf8)
        #expect(try APNsCredentials(secret: secret) == APNsCredentials(keyID: "ABC123DEFG", teamID: "T", privateKeyPEM: "pem"))
    }

    static func jwt(of request: URLRequest) throws -> String {
        let header = try #require(request.value(forHTTPHeaderField: "authorization"))
        try #require(header.hasPrefix("bearer "))
        return String(header.dropFirst("bearer ".count))
    }

    static func decode(_ part: String) throws -> Data {
        var base64 = part.replacing("-", with: "+").replacing("_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return try #require(Data(base64Encoded: base64))
    }
}
