// APNsCredentials: the team's APNs auth key from the Keychain item that
// `make apns-key` stores (spec_architecture.md §2.4).

public import Foundation
import Security

/// The auth key: its 10-character id, the team id, and the PEM P-256
/// private key of the `.p8` file.
public struct APNsCredentials: Sendable, Hashable, Codable {
    public var keyID: String
    public var teamID: String
    /// The contents of the `.p8` file (the secret's `p8`).
    public var privateKeyPEM: String

    public init(keyID: String, teamID: String, privateKeyPEM: String) {
        self.keyID = keyID
        self.teamID = teamID
        self.privateKeyPEM = privateKeyPEM
    }

    private enum CodingKeys: String, CodingKey {
        case keyID
        case teamID
        case privateKeyPEM = "p8"
    }

    /// Parses the Keychain secret `{"keyID": …, "teamID": …, "p8": …}`.
    public init(secret: Data) throws(PushError) {
        do {
            self = try JSONDecoder().decode(Self.self, from: secret)
        } catch {
            throw .invalidKey("The APNs key item is not valid JSON.")
        }
    }
}

/// Where the push client finds the credentials.
public protocol APNsCredentialSource: Sendable {
    /// The credentials, or `nil` when no key is installed.
    func credentials() throws(PushError) -> APNsCredentials?
}

/// Fixed credentials (tests) or none.
public struct StaticAPNsCredentials: APNsCredentialSource {
    public let value: APNsCredentials?

    public init(_ value: APNsCredentials?) {
        self.value = value
    }

    public func credentials() -> APNsCredentials? {
        value
    }
}

/// The generic-password item of service `<BUNDLE_ID>.apns` in the login Keychain.
public struct KeychainAPNsCredentials: APNsCredentialSource {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func credentials() throws(PushError) -> APNsCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw .invalidKey("The APNs key item has no secret.")
            }
            return try APNsCredentials(secret: data)
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(Int(status))
        }
    }
}
