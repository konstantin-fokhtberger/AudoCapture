import AppKit
import Foundation
import Testing
@testable import AudoCaptureCore

@MainActor
struct RecordingEnvironmentMonitorTests {
    @Test func hardwareChangesIgnoreAdditionsButStopForRemovalOrRouteChanges() {
        let original = AudioHardwareSnapshot(devices: [1, 2], input: 1, output: 2)
        #expect(!original.requiresStop(comparedTo: original))
        #expect(!AudioHardwareSnapshot(devices: [1, 2, 3], input: 1, output: 2).requiresStop(comparedTo: original))
        #expect(AudioHardwareSnapshot(devices: [1], input: 1, output: 2).requiresStop(comparedTo: original))
        #expect(AudioHardwareSnapshot(devices: [1, 2], input: 2, output: 2).requiresStop(comparedTo: original))
        #expect(AudioHardwareSnapshot(devices: [1, 2], input: 1, output: 1).requiresStop(comparedTo: original))
    }

    @Test func notificationsUseCorrectCentersAndUnsubscribeOnRelease() {
        let workspace = NotificationCenter()
        let application = NotificationCenter()
        let log = EnvironmentEventLog()
        var monitor: RecordingEnvironmentMonitor? = RecordingEnvironmentMonitor(
            onInterruption: { log.reasons.append($0) }, onRefresh: { log.refreshes += 1 },
            workspaceCenter: workspace, applicationCenter: application, observeAudioHardware: false, displayConfiguration: { log.displays })
        #expect(monitor?.warnings.isEmpty == true)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(log.reasons.count == 1) // unchanged display notification must not stop capture
        log.displays = [2, 1, 2]
        application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(log.reasons.count == 2)
        #expect(log.reasons[0].contains("сон"))
        #expect(log.reasons[1].contains("дисплеев"))
        #expect(log.refreshes == 4)
        monitor = nil
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(log.reasons.count == 2)
        #expect(log.refreshes == 4)
    }
}

@MainActor private final class EnvironmentEventLog {
    var reasons: [String] = []
    var refreshes = 0
    var displays: [UInt32] = [1, 1]
}
