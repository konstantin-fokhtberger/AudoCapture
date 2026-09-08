import AVFoundation
import CoreAudio
import Foundation

public struct MicrophoneDevice: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let isDefault: Bool

    public init(id: UInt32, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public protocol MicrophoneDeviceProviding: Sendable {
    func availableMicrophones() -> [MicrophoneDevice]
}

public struct MicrophoneDeviceCatalog: MicrophoneDeviceProviding {
    public init() {}

    public func availableMicrophones() -> [MicrophoneDevice] {
        let defaultID = defaultInputDeviceID()
        return inputDeviceIDs().compactMap { deviceID in
            guard let name = name(for: deviceID) else { return nil }
            return MicrophoneDevice(id: deviceID, name: name, isDefault: deviceID == defaultID)
        }
    }

    func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private func inputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard sizeStatus == noErr, size > 0, Int(size) % MemoryLayout<AudioDeviceID>.size == 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard dataStatus == noErr else { return [] }

        return deviceIDs.filter { hasInputChannels(deviceID: $0) }
    }

    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr, size >= MemoryLayout<AudioBufferList>.size else { return false }

        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        let bufferListPointer = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        defer { storage.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        guard dataStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let channelCount = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private func name(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanagedName else { return nil }
        return unmanagedName.takeRetainedValue() as String
    }
}
