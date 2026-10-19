import Foundation
import Network
import Security

/// A throwaway TLS identity, so a speaker can be stood up on this machine.
///
/// **Real TLS, on purpose.** A seam in `CastLink` for the tests to reach through would
/// mean the code under test is not the code that runs. The framing, the handshake and the
/// read loop are where a cast goes wrong, so they must run for real. `CastLink` already
/// accepts any certificate, because a Chromecast's certificate is self-signed, so a
/// certificate made here works the same way.
///
/// The identity is made with `openssl`, not built by hand. A wrong DER blob fails later as
/// a handshake error, far from the real mistake.
enum SelfSigned {

    private static let made = OSAllocatedUnfairLockBox<sec_identity_t?>(nil)

    /// Held across the check and the mint together.
    ///
    /// **Only one identity is made for the whole run.** Without this lock, the cast suites,
    /// which start side by side, could each find no identity and each mint one. Several
    /// `SecPKCS12Import` calls at once can fail with `-26276`, and that fails a test that has
    /// nothing to do with certificates. With the lock, the second caller waits for the first
    /// caller's identity.
    private static let minting = NSLock()

    /// One identity for the whole test run. Minting takes a moment, and nothing the tests
    /// check depends on the identity being new.
    static func identity() throws -> sec_identity_t {
        try minting.withLock {
            if let already = made.value { return already }

            let identity = try mint()
            made.value = identity
            return identity
        }
    }

    private static func mint() throws -> sec_identity_t {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rpm-fake-speaker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let p12 = dir.appendingPathComponent("id.p12")
        let password = "rpm"

        try run("/opt/homebrew/bin/openssl", [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", dir.appendingPathComponent("k.pem").path,
            "-out", dir.appendingPathComponent("c.pem").path,
            "-days", "1", "-subj", "/CN=a fake speaker",
        ])

        try run("/opt/homebrew/bin/openssl", [
            "pkcs12", "-export", "-legacy",
            "-inkey", dir.appendingPathComponent("k.pem").path,
            "-in", dir.appendingPathComponent("c.pem").path,
            "-out", p12.path, "-passout", "pass:\(password)",
        ])

        var items: CFArray?
        let status = SecPKCS12Import(try Data(contentsOf: p12) as CFData,
                                     [kSecImportExportPassphrase as String: password] as CFDictionary,
                                     &items)
        guard status == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let raw = first[kSecImportItemIdentity as String]
        else { throw Trouble.wouldNotImport(status) }

        let identity = sec_identity_create(raw as! SecIdentity)
        guard let identity else { throw Trouble.wouldNotImport(status) }

        return identity
    }

    enum Trouble: Error { case wouldNotImport(OSStatus), openssl(String) }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments

        let errors = Pipe()
        task.standardError = errors
        task.standardOutput = Pipe()

        try task.run()
        let said = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw Trouble.openssl(String(decoding: said, as: UTF8.self))
        }
    }
}

/// A lock around one value. `sec_identity_t` is not `Sendable`, and the value is shared
/// across the test run, so the lock guards every access.
final class OSAllocatedUnfairLockBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
