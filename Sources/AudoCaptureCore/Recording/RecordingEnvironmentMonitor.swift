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
                observeAudioHardware: Bool = true,
                displayConfiguration: @escaping @MainActor @Sendable () -> [UInt32] = {
                    [CGMainDisplayID()] + NSScreen.screens.compactMap {
                        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    }.sorted()
                }) {
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
        let displayState = DisplayConfigurationState(displayConfiguration())
        let displayToken = applicationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if displayState.update(displayConfiguration()) {
                    onInterruption("Конфигурация дисплеев изменилась. Дождитесь сохранения и начните новую запись.")
                }
                onRefresh()
            }
        }
        notifications.append((applicationCenter, displayToken))
        guard observeAudioHardware else { return }
        let hardwareState = AudioHardwareChangeState()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let listener: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in
                    if hardwareState.update() {
                        onInterruption("Аудиоустройства изменились. Проверьте микрофон и выход звука, затем начните новую запись.")
                    }
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


struct AudioHardwareSnapshot: Equatable {
    let devices: Set<AudioObjectID>
    let input: AudioObjectID
    let output: AudioObjectID

    func requiresStop(comparedTo previous: Self) -> Bool {
        input != previous.input || output != previous.output || !previous.devices.isSubset(of: devices)
    }

    static func read() -> Self? {
        func values(_ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            let object = AudioObjectID(kAudioObjectSystemObject)
            guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
                  size > 0, size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { return nil }
            var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            let status = result.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!)
            }
            guard status == noErr else { return nil }
            return Array(result.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
        }
        guard let devices = values(kAudioHardwarePropertyDevices),
              let input = values(kAudioHardwarePropertyDefaultInputDevice)?.first,
              let output = values(kAudioHardwarePropertyDefaultOutputDevice)?.first else { return nil }
        return Self(devices: Set(devices), input: input, output: output)
    }
}

@MainActor private final class AudioHardwareChangeState {
    private var previous = AudioHardwareSnapshot.read()

    func update() -> Bool {
        let current = AudioHardwareSnapshot.read()
        defer { previous = current }
        // Unknown hardware state remains conservative; never silently ignore a failed read.
        guard let previous, let current else { return true }
        return current.requiresStop(comparedTo: previous)
    }
}


@MainActor private final class DisplayConfigurationState {
    private var previous: [UInt32]
    init(_ initial: [UInt32]) { previous = initial }
    func update(_ current: [UInt32]) -> Bool {
        defer { previous = current }
        return current != previous
    }
}
