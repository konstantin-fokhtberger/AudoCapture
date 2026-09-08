import AudoCaptureCore
import Foundation

@MainActor
final class ApplicationModel: ObservableObject {
    private let environmentMonitor: RecordingEnvironmentMonitor
    let recordingViewModel: RecordingViewModel

    init(recordingViewModel: RecordingViewModel = RecordingViewModel()) {
        self.recordingViewModel = recordingViewModel
        environmentMonitor = RecordingEnvironmentMonitor(
            onInterruption: { [weak recordingViewModel] in recordingViewModel?.interruptRecording($0) },
            onRefresh: { [weak recordingViewModel] in recordingViewModel?.refreshEnvironment() })
        if !environmentMonitor.warnings.isEmpty {
            recordingViewModel.environmentWarning = environmentMonitor.warnings.joined(separator: "\n")
        }
    }
}
