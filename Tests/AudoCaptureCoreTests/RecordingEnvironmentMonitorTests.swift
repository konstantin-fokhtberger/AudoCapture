import AppKit
import Foundation
import Testing
@testable import AudoCaptureCore

@MainActor
struct RecordingEnvironmentMonitorTests {
    @Test func notificationsUseCorrectCentersAndUnsubscribeOnRelease() {
        let workspace = NotificationCenter()
        let application = NotificationCenter()
        let log = EnvironmentEventLog()
        var monitor: RecordingEnvironmentMonitor? = RecordingEnvironmentMonitor(
            onInterruption: { log.reasons.append($0) }, onRefresh: { log.refreshes += 1 },
            workspaceCenter: workspace, applicationCenter: application, observeAudioHardware: false)
        #expect(monitor?.warnings.isEmpty == true)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(log.reasons.count == 2)
        #expect(log.reasons[0].contains("сон"))
        #expect(log.reasons[1].contains("дисплеев"))
        #expect(log.refreshes == 2)
        monitor = nil
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(log.reasons.count == 2)
        #expect(log.refreshes == 2)
    }
}

@MainActor private final class EnvironmentEventLog {
    var reasons: [String] = []
    var refreshes = 0
}
