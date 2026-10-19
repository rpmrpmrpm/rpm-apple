import Foundation
import CryptoKit
import RPMKit

/// This device's key on the home network: an ECDSA P-256 key, made once and kept in the keychain.
/// Its public half (SubjectPublicKeyInfo DER) is what a computer pairs with. The device id is
/// derived from it in the same way as in the desktop's `PeerIdentity.cs`.
public struct PeerIdentity: Sendable {
    private let key: P256.Signing.PrivateKey

    /// SubjectPublicKeyInfo DER.
    public var publicKey: Data { key.publicKey.derRepresentation }

    public var deviceId: String { PeerWire.id(for: publicKey) }

    init(key: P256.Signing.PrivateKey) {
        self.key = key
    }

    /// Signs `data` with SHA-256. The signature is r followed by s, 64 bytes (IEEE P1363), not DER.
    /// The computer checks it with .NET's `ECDsa.VerifyData` and no format argument, and that call
    /// rejects DER.
    public func sign(_ data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }

    private static let entry = "rpm.peer.key"

    /// The stored key, or a new key on first use. A stored key that cannot be read is replaced.
    /// Computers paired with the old key must pair again.
    public static func load(from store: any SecretStore) async -> PeerIdentity {
        if let raw = await store.read(entry), let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            return PeerIdentity(key: key)
        }
        let made = P256.Signing.PrivateKey()
        await store.write(entry, made.rawRepresentation)
        return PeerIdentity(key: made)
    }
}
