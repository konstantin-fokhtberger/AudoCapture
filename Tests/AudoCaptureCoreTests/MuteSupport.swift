@testable import AudoCaptureCore

extension RecordingCaptureService {
    func setMuted(_ muted: Bool) {}
}
extension RecordingControlling {
    func setMuted(microphone: Bool, system: Bool) async {}
}
