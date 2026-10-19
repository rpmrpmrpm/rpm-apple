import Foundation
import Security
import CryptoKit

/// The computers on the home network that this device may talk to, by address, with the public key
/// each one advertised.
///
/// A computer running rpm serves TLS with a self-signed certificate made from its own key, at a bare
/// IP address. For a pinned address, the certificate's public key must match the key the computer
/// advertised, byte for byte. Names, chains and dates are not checked. `RPM.Core/Sharing/PeerCertificate.cs`
/// does the same on the desktop. All other hosts are checked the usual way. So a computer's redirect
/// to cloud storage is checked against the system's trusted authorities.
///
/// There is one table for the whole process, because the audio feed and the home network's own requests
/// each open their own `URLSession`. Both must give the same answer.
public final class PeerPins: @unchecked Sendable {
    public static let shared = PeerPins()

    private let lock = NSLock()

    /// Maps an address to the key's X9.63 form (`04 ‖ X ‖ Y`). This is the form that
    /// `SecKeyCopyExternalRepresentation` returns for a certificate's key.
    private var pins: [String: Data] = [:]

    public init() {}

    /// Pins `address` to the key in `spki`, the SubjectPublicKeyInfo DER that a computer advertises.
    /// A key that is not P-256 is not pinned.
    public func pin(_ address: String, spki: Data) {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: spki) else { return }
        lock.withLock { pins[address] = key.x963Representation }
    }

    public func isPinned(_ address: String) -> Bool {
        lock.withLock { pins[address] != nil }
    }

    /// The answer to a TLS challenge. For a pinned address, the certificate's key must match the pinned
    /// key. For every other host, the system decides. Call this from
    /// `urlSession(_:didReceive:completionHandler:)`.
    public func answer(_ challenge: URLAuthenticationChallenge)
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              let wanted = lock.withLock({ pins[space.host] })
        else { return (.performDefaultHandling, nil) }

        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let held = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              held == wanted
        else { return (.cancelAuthenticationChallenge, nil) }

        return (.useCredential, URLCredential(trust: trust))
    }
}
