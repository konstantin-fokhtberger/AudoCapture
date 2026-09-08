import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var applicationModel: ApplicationModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recordingViewModel = applicationModel?.recordingViewModel else {
            return .terminateNow
        }

        guard recordingViewModel.shouldDelayTermination else {
            return .terminateNow
        }

        Task { @MainActor in
            let ready = await recordingViewModel.prepareForTermination()
            NSApp.reply(toApplicationShouldTerminate: ready)
        }

        return .terminateLater
    }
}
