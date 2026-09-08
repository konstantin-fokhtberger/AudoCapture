import AudoCaptureCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel
    @AppStorage("compactAppearance") private var isCompact = true

    var body: some View {
        Group {
            if isCompact { compactView }
            else { fullView }
        }
        .fixedSize()
        .background(CompactWindowLevel(isCompact: isCompact))
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

    private var compactView: some View {
        HStack(spacing: 16) {
            Button(action: toggleRecording) {
                Image(systemName: viewModel.status == .recording ? "stop.fill" : "record.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.status == .recording ? .red : .accentColor)
            .disabled(isTransitioning || viewModel.updatingMute)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(viewModel.status == .recording ? "Остановить и сохранить" : "Начать запись")
            .help(viewModel.status == .recording ? "Остановить и сохранить" : "Начать запись")

            VStack(spacing: 3) {
                if isTransitioning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: hasWarning ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(hasWarning ? .orange : (viewModel.status == .recording ? .red : Color.secondary))
                }
                Text(viewModel.status == .recording ? (viewModel.microphoneMuted && viewModel.systemMuted ? "ТИШИНА" : "ON AIR") : compactStatus)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .frame(width: 62)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusTitle)
            .accessibilityValue(viewModel.elapsedText)
            .help(statusTitle + (hasWarning ? ". Разверните окно для подробностей." : ""))
            sourceButtons
            appearanceButton
        }
        .padding(10)
        .frame(width: 278, height: 56)
    }

    private var sourceButtons: some View {
        HStack(spacing: 8) {
            muteButton(microphone: true)
            muteButton(microphone: false)
        }
    }

    private func muteButton(microphone: Bool) -> some View {
        let muted = microphone ? viewModel.microphoneMuted : viewModel.systemMuted
        let name = microphone ? "Микрофон" : "Системный звук"
        return Button { viewModel.toggleMute(microphone: microphone) } label: {
            Image(systemName: microphone ? (muted ? "mic.slash.fill" : "mic.fill") : "headphones")
                .font(.system(size: 15))
                .foregroundStyle(muted ? Color.secondary : Color.accentColor)
                .frame(width: 24, height: 28)
                .overlay {
                    if !microphone && muted {
                        Rectangle().fill(Color.secondary).frame(width: 23, height: 2).rotationEffect(.degrees(-45))
                    }
                }
        }
        .buttonStyle(.borderless)
        .disabled(isTransitioning || viewModel.updatingMute)
        .accessibilityLabel(name)
        .accessibilityValue(muted ? "Не попадает в запись" : "Записывается")
        .help(name + (muted ? ": включить в запись" : ": исключить из записи"))
    }

    private var appearanceButton: some View {
        Button { isCompact.toggle() } label: {
            Image(systemName: isCompact ? "chevron.down" : "chevron.up")
                .frame(width: 22, height: 26)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isCompact ? "Развернуть окно" : "Свернуть окно")
        .help(isCompact ? "Развернуть настройки" : "Компактный вид")
    }

    private var isTransitioning: Bool { viewModel.status == .starting || viewModel.status == .processing }
    private var hasWarning: Bool {
        viewModel.errorMessage != nil || viewModel.noticeMessage != nil || viewModel.environmentWarning != nil ||
        viewModel.isMicrophonePermissionMissing || viewModel.isScreenRecordingPermissionMissing ||
        viewModel.status == .partial || viewModel.status == .failed ||
        (viewModel.status == .recording && viewModel.activeTracks.count != 2)
    }
    private var compactStatus: String {
        if hasWarning { return "ВНИМАНИЕ" }
        switch viewModel.status {
        case .starting: return "ЗАПУСК"
        case .processing: return "СОХРАНЕНИЕ"
        case .completed: return "СОХРАНЕНО"
        default: return "ГОТОВО"
        }
    }
    private func toggleRecording() {
        if viewModel.status == .recording { viewModel.stopRecording() }
        else { viewModel.startRecording() }
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("AudoCapture").font(.title2.bold())
                Spacer()
                Text(statusTitle).foregroundStyle(statusColor)
                appearanceButton
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
                .disabled(isTransitioning || viewModel.updatingMute)
            }

            HStack {
                sourceButtons
                Text("Источники записи").font(.caption).foregroundStyle(.secondary)
                Spacer()
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
                Text(viewModel.microphoneMuted && viewModel.systemMuted ? "Оба источника выключены: записывается тишина" : "Записывается: " + viewModel.activeTracks.filter { $0 == .microphone ? !viewModel.microphoneMuted : !viewModel.systemMuted }.map { $0 == .microphone ? "микрофон" : "системный звук" }.joined(separator: " + "))
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
