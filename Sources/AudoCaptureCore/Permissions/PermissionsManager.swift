import AppKit
import AVFoundation
import CoreGraphics
import Foundation

public struct PermissionsSnapshot: Sendable {
    public let microphoneGranted: Bool
    public let screenCaptureGranted: Bool
}

public struct PermissionsManager: Sendable {
    public init() {}

    public func currentStatus() -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphoneGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            screenCaptureGranted: CGPreflightScreenCaptureAccess()
        )
    }

    public func requestRequiredPermissions() async throws {
        let micGranted = try await requestMicrophone()
        try Task.checkCancellation()
        let screenGranted = try await requestScreenCapture()

        guard micGranted else {
            throw RecordingError.microphonePermissionDenied
        }
        guard screenGranted else {
            throw RecordingError.screenCapturePermissionDenied
        }
    }

    public func openSystemSettingsForMicrophone() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    public func openSystemSettingsForScreenCapture() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestMicrophone() async throws -> Bool {
        try await awaitPermissionReply { completion in
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
    }

    private func requestScreenCapture() async throws -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return try await awaitPermissionReply { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                completion(CGRequestScreenCaptureAccess())
            }
        }
    }
}

/// Cancel waiting without claiming to cancel the OS-owned permission dialog.
func awaitPermissionReply(
    _ request: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
) async throws -> Bool {
    let reply = PermissionReply()
    return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            if reply.install(continuation) {
                request { reply.complete(.success($0)) }
            }
        }
    } onCancel: {
        reply.complete(.failure(CancellationError()))
    }
}

private final class PermissionReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Error>?
    private var result: Result<Bool, Error>?

    func install(_ continuation: CheckedContinuation<Bool, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func complete(_ result: Result<Bool, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(with: result)
    }
}
