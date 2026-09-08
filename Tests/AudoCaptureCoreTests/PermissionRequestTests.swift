import Foundation
import Testing
@testable import AudoCaptureCore

struct PermissionRequestTests {
    @Test func cancellationReturnsWithoutWaitingForOSReply() async throws {
        let callback = PermissionCallback()
        let task = Task { try await awaitPermissionReply { callback.install($0) } }
        for _ in 0..<100 {
            if callback.installed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(callback.installed)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
        // A late OS completion must not resume the continuation a second time.
        callback.reply(true)
        callback.reply(false)
    }

    @Test func permissionReplyIsReturned() async throws {
        let granted = try await awaitPermissionReply { $0(true) }
        let denied = try await awaitPermissionReply { $0(false) }
        #expect(granted)
        #expect(!denied)
    }
}

private final class PermissionCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (Bool) -> Void)?
    var installed: Bool { lock.lock(); defer { lock.unlock() }; return callback != nil }
    func install(_ callback: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); defer { lock.unlock() }; self.callback = callback
    }
    func reply(_ granted: Bool) {
        lock.lock(); let completion = callback; lock.unlock(); completion?(granted)
    }
}
