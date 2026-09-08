import AudoCaptureCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("AudoCapture").font(.title2.bold())
                Spacer()
                Text(statusTitle).foregroundStyle(statusColor)
            }
            Text("Микрофон и весь системный звук в одном M4A")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack {
                Text(viewModel.elapsedText)
                    .font(.system(size: 38, weight: .medium, design: .monospaced))
                    .accessibilityLabel("Длительность записи")
                Spacer()
                if viewModel.status == .starting || viewModel.status == .processing {
                    ProgressView().controlSize(.small)
                }
                Button(viewModel.status == .recording ? "Остановить и сохранить" : "Начать запись") {
                    if viewModel.status == .recording { viewModel.stopRecording() }
                    else { viewModel.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.status == .starting || viewModel.status == .processing)
            }

            Picker("Микрофон", selection: $viewModel.selectedMicrophoneID) {
                if viewModel.availableMicrophones.isEmpty {
                    Text("Нет доступного устройства").tag(Optional<UInt32>.none)
                }
                ForEach(viewModel.availableMicrophones) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .disabled(viewModel.shouldDelayTermination)

            if viewModel.status == .recording {
                Text("Записывается: " + viewModel.activeTracks.map { $0 == .microphone ? "микрофон" : "системный звук" }.joined(separator: " + "))
                    .font(.subheadline)
                    .foregroundStyle(viewModel.activeTracks.count == 2 ? Color.secondary : Color.orange)
            }

            if viewModel.isMicrophonePermissionMissing || viewModel.isScreenRecordingPermissionMissing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Разрешите доступ в настройках macOS. Без разрешения соответствующий источник не запишется.")
                        .font(.subheadline)
                    HStack {
                        if viewModel.isMicrophonePermissionMissing {
                            Button("Доступ к микрофону") { viewModel.openMicrophoneSettings() }
                        }
                        if viewModel.isScreenRecordingPermissionMissing {
                            Button("Доступ к системному звуку") { viewModel.openScreenRecordingSettings() }
                        }
                    }
                }
            }

            if let warning = viewModel.environmentWarning {
                Text(warning).font(.subheadline).foregroundStyle(.orange)
            }
            if let notice = viewModel.noticeMessage {
                Text(notice).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let error = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Text(viewModel.canRetryExport
                         ? "Исходники сохранены. Проверьте свободное место и повторите сохранение."
                         : "Проверьте устройства и разрешения. Если доступ не обновился, перезапустите приложение.")
                        .foregroundStyle(.secondary)
                }.font(.subheadline)
            }
            if viewModel.canRetryExport {
                Button("Повторить сохранение") { viewModel.retryExport() }
                    .disabled(viewModel.shouldDelayTermination)
            }

            if let directory = viewModel.lastOutputDirectory {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.lastOutputFile.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Сохранение не завершено")
                        .font(.subheadline.weight(.medium)).textSelection(.enabled)
                    if let start = viewModel.lastRecordingStart {
                        Text("Начало: \(start)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Показать в Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: viewModel.lastOutputFile ?? directory)
                        ])
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task { viewModel.refreshEnvironment() }
        .task(id: viewModel.status) {
            guard viewModel.status == .recording else { return }
            while !Task.isCancelled {
                viewModel.updateElapsedTime()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    private var statusTitle: String {
        switch viewModel.status {
        case .idle: "Готово к записи"
        case .starting: "Запуск…"
        case .recording: viewModel.activeTracks.count == 2 ? "Идёт запись" : "Запись одного источника"
        case .processing: "Сохранение…"
        case .completed: "Сохранено"
        case .partial: "Сохранено с ограничениями"
        case .failed: "Ошибка"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .recording, .failed: .red
        case .partial: .orange
        case .completed: .green
        default: .secondary
        }
    }
}
