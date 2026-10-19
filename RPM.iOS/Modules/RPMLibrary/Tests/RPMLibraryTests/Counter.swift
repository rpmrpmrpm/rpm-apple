import Foundation

/// A counter that can be bumped from any thread. The lock makes that safe, which is why the class is
/// marked `@unchecked Sendable`.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
