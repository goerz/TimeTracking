// APNsTokenSigner: the ES256 provider token, reused for 50 minutes
// (architecture.md §2.4).

import CryptoKit
public import Foundation

/// Signs `{"alg":"ES256","kid":<key id>}.{"iss":<team>,"iat":<now>}` with the
/// auth key and hands out the same token until it is 50 minutes old.
public struct APNsTokenSigner: Sendable {
    /// How long a token is reused.
    public static let lifetime: TimeInterval = 50 * 60

    public let credentials: APNsCredentials
    private let key: P256.Signing.PrivateKey
    private var current: (token: String, issuedAt: Date)?

    public init(credentials: APNsCredentials) throws(PushError) {
        self.credentials = credentials
        do {
            self.key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        } catch {
            throw .invalidKey("The APNs key is not a P-256 private key.")
        }
    }

    /// The token at `now`: the cached one while younger than 50 minutes,
    /// otherwise a new one issued at `now`.
    public mutating func token(at now: Date) throws(PushError) -> String {
        if let current, now.timeIntervalSince(current.issuedAt) < Self.lifetime, now >= current.issuedAt {
            return current.token
        }
        let issuedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let header = #"{"alg":"ES256","kid":"\#(credentials.keyID)"}"#
        let claims = #"{"iss":"\#(credentials.teamID)","iat":\#(Int64(issuedAt.timeIntervalSince1970))}"#
        let input = Self.base64URL(Data(header.utf8)) + "." + Self.base64URL(Data(claims.utf8))
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try key.signature(for: Data(input.utf8))
        } catch {
            throw .invalidKey("Signing the APNs token failed.")
        }
        let token = input + "." + Self.base64URL(signature.rawRepresentation)
        current = (token, issuedAt)
        return token
    }

    /// Base64url without padding (RFC 7515).
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }
}
