import SwiftUI

@main
struct AudoCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var applicationModel = ApplicationModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: applicationModel.recordingViewModel)
                .task {
                    appDelegate.applicationModel = applicationModel
                }
        }
        .windowResizability(.contentSize)
    }
}
