import AppKit
import CoreAudio
import Foundation

/// App-lifetime OS subscriptions. Audio callbacks only schedule work on the main actor.
public final class RecordingEnvironmentMonitor: @unchecked Sendable {
    public private(set) var warnings: [String] = []
    private var notifications: [(NotificationCenter, NSObjectProtocol)] = []
    private var audioListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    @MainActor
    public init(onInterruption: @escaping @MainActor @Sendable (String) -> Void,
                onRefresh: @escaping @MainActor @Sendable () -> Void,
                workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
                applicationCenter: NotificationCenter = .default,
                observeAudioHardware: Bool = true) {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, reason: String?) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if let reason { onInterruption(reason) }
                    else { onRefresh() }
                }
            }
            notifications.append((center, token))
        }
        observe(workspaceCenter, NSWorkspace.willSleepNotification,
                reason: "Mac переходит в сон. Запись остановлена; дождитесь сохранения после пробуждения.")
        observe(workspaceCenter, NSWorkspace.didWakeNotification, reason: nil)
        observe(applicationCenter, NSApplication.didBecomeActiveNotification, reason: nil)
        observe(applicationCenter, NSApplication.didChangeScreenParametersNotification,
                reason: "Конфигурация дисплеев изменилась. Дождитесь сохранения и начните новую запись.")
        guard observeAudioHardware else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let listener: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in
                    onInterruption("Аудиоустройства изменились. Проверьте микрофон и выход звука, затем начните новую запись.")
                    onRefresh()
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            if status == noErr { audioListeners.append((address, listener)) }
            else { warnings.append("Не удалось подключить наблюдение за аудиоустройствами (\(status)). Отключение устройства может не остановить запись автоматически.") }
        }
    }

    deinit {
        for (center, token) in notifications { center.removeObserver(token) }
        for (var address, listener) in audioListeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }
}
