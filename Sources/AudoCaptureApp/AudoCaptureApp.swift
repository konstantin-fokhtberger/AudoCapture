import SwiftUI

@main
struct AudoCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var applicationModel = ApplicationModel()

    @AppStorage("compactAppearance") private var isCompact = true

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: applicationModel.recordingViewModel)
                .task {
                    appDelegate.applicationModel = applicationModel
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Toggle("Компактный режим", isOn: $isCompact)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
