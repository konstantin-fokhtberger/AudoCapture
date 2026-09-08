import Foundation
import Testing
@testable import AudoCaptureCore

struct AudioSyncCoordinatorTests {
    @Test
    func makeSessionPlanBuildsExpectedFormats() throws {
        let coordinator = AudioSyncCoordinator(sampleRate: 44_100)

        let plan = try coordinator.makeSessionPlan(startedAt: Date(timeIntervalSince1970: 123))

        #expect(plan.startedAt == Date(timeIntervalSince1970: 123))
        #expect(plan.micConfig.kind == .microphone)
        #expect(plan.systemConfig.kind == .system)
        #expect(plan.micConfig.sampleRate == 44_100)
        #expect(plan.systemConfig.sampleRate == 44_100)
        #expect(plan.micConfig.channels == 1)
        #expect(plan.systemConfig.channels == 2)
        #expect(plan.micFormat.sampleRate == 44_100)
        #expect(plan.systemFormat.sampleRate == 44_100)
        #expect(plan.micFormat.channelCount == 1)
        #expect(plan.systemFormat.channelCount == 2)
    }
}
