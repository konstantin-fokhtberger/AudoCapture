# Доказательства отдельного code quality review

Дата: 2026-09-08. Это characterization probes: они проверяют наличие дефекта, а не правильное поведение. Успех пяти проб означает воспроизведение проблем. Рабочий код и штатные тесты не менялись.

## Результат запуска

```text
Build complete! (16.49s)
AUDIT collision: shared directory; previous artifact removed
AUDIT conversion frames: [2229, 0, 0, 0, 0, 0]
AUDIT writer: first=16, second=32, fileFrames=16
AUDIT manager: 2 successful starts, only 1 stop per source
AUDIT termination: returned while state=processing
✔ Test run with 25 tests in 6 suites passed after 5.044 seconds.
```

20 исходных тестов + 5 диагностических проб. Проверки используют синтетические буферы и fake capture services, не записывают реальный звук. Тест коллизии удаляет только специально созданный временный файл.

## Воспроизведение

1. Скопировать Package.swift, Sources и Tests в отдельный временный каталог, без .build.
2. Добавить следующий файл в Tests/AudoCaptureCoreTests/QualityAuditProbes.swift временной копии.
3. Второй фрагмент добавить в конец RecordingViewModelTests.swift временной копии: он использует private TestRecordingController из того же файла.
4. Выполнить swift test полным Xcode, с отдельным scratch path и доступными временными module cache. Не переносить эти assertions в обычные regression tests без инверсии ожидаемого поведения после исправления.

Использованный временный каталог: `/var/folders/mz/2mdv3gzj19vf_7mmcb62vtgm0000gn/T/audocapture-quality-_5z5mycz`.

### QualityAuditProbes.swift

```swift
import AVFoundation
import Foundation
import Testing
@testable import AudoCaptureCore

// Characterization probes: they assert observed defects, not correct behavior.
struct QualityAuditProbes {
    @Test func conversionDropsFollowingBuffers() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let output = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let converter = try #require(AVAudioConverter(from: input, to: output))
        var frames: [UInt32] = []
        for _ in 0..<6 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 2048))
            buffer.frameLength = 2048
            for i in 0..<2048 { buffer.floatChannelData![0][i] = 0.2 }
            frames.append(try AVAudioPCMBuffer.makeCopy(from: buffer, using: converter, targetFormat: output).frameLength)
        }
        print("AUDIT conversion frames: \(frames)")
        #expect(frames[0] > 0)
        #expect(frames.dropFirst().allSatisfy { $0 == 0 })
    }

    @Test func directoryCollisionCanDeletePreviousArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingDirectoryManager(recordingsRootOverride: root)
        let date = Date(timeIntervalSince1970: 100)
        let first = try manager.createSessionDirectory(at: date)
        try Data("previous session".utf8).write(to: first.micPCM)
        let second = try manager.createSessionDirectory(at: date)
        #expect(first.root == second.root)
        manager.removeSessionDirectory(at: second.root)
        #expect(!FileManager.default.fileExists(atPath: first.micPCM.path))
        print("AUDIT collision: shared directory; previous artifact removed")
    }

    @Test func writerReopenKeepsOldFrameCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let writer = PCMFileWriter(url: root.appendingPathComponent("test.wav"), format: format)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16
        for i in 0..<16 { buffer.int16ChannelData![0][i] = 0 }
        try writer.prepare(); try writer.append(buffer)
        let first = writer.finalize()
        try writer.prepare(); try writer.append(buffer)
        let second = writer.finalize()
        let actual = try AVAudioFile(forReading: root.appendingPathComponent("test.wav")).length
        print("AUDIT writer: first=\(first), second=\(second), fileFrames=\(actual)")
        #expect(first == 16)
        #expect(second == 32)
        #expect(actual == 16)
    }

    @Test func managerAcceptsTwoConcurrentStarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let permission = AuditPermissions()
        let mic = AuditCapture()
        let system = AuditCapture()
        let manager = RecordingManager(permissionsManager: permission,
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            encoder: AuditEncoder(), captureFactory: AuditFactory(mic: mic, system: system),
            folderOpener: AuditFolder(), microphoneCatalog: AuditCatalog())
        let first = Task { try await manager.startRecording() }
        for _ in 0..<100 {
            if await permission.count >= 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let second = Task { try await manager.startRecording() }
        for _ in 0..<100 {
            if await permission.count >= 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let admitted = await permission.count
        await permission.release()
        _ = try await first.value
        _ = try await second.value
        #expect(admitted == 2)
        #expect(await mic.starts == 2)
        _ = try await manager.stopRecording(openFolder: false)
        #expect(await mic.stops == 1)
        print("AUDIT manager: 2 successful starts, only 1 stop per source")
    }
}

private actor AuditPermissions: PermissionsProviding {
    private(set) var count = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    nonisolated func currentStatus() -> PermissionsSnapshot { .init(microphoneGranted: true, screenCaptureGranted: true) }
    nonisolated func openSystemSettingsForMicrophone() {}
    nonisolated func openSystemSettingsForScreenCapture() {}
    func requestRequiredPermissions() async throws {
        count += 1
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() {
        released = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
private actor AuditCapture: RecordingCaptureService {
    nonisolated let sourceDescription: String? = "audit fake"
    private(set) var starts = 0
    private(set) var stops = 0
    func start() async throws { starts += 1 }
    func stop() async throws -> AVAudioFramePosition { stops += 1; return 0 }
}
private struct AuditFactory: RecordingCaptureFactory {
    let mic: AuditCapture
    let system: AuditCapture
    func makeCapturePair(layout: RecordingDirectoryLayout, plan: AudioSessionPlan, logger: AppLogger, preferredMicrophoneDeviceID: UInt32?) -> RecordingCapturePair {
        .init(microphone: mic, system: system)
    }
}
private struct AuditEncoder: MP3Encoding {
    func encode(inputURL: URL, outputURL: URL, bitrate: Int) async throws {}
}
private struct AuditFolder: RecordingsFolderOpening { func open(directoryURL: URL) async {} }
private struct AuditCatalog: MicrophoneDeviceProviding { func availableMicrophones() -> [MicrophoneDevice] { [] } }
```

### Дополнение к RecordingViewModelTests.swift

```swift
extension RecordingViewModelTests {
    @Test func auditTerminationReturnsWhileProcessingIsStillActive() async throws {
        let manager = TestRecordingController(startMode: .success(), stopMode: .pending)
        let viewModel = RecordingViewModel(manager: manager)
        viewModel.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { viewModel.status == .recording }
        viewModel.stopRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { viewModel.status == .processing }
        await viewModel.prepareForTermination()
        let returnedState = viewModel.status
        await manager.finishStop()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { viewModel.status == .completed }
        print("AUDIT termination: returned while state=\(returnedState)")
        #expect(returnedState == .processing)
    }
}
```

## SHA-256 проверенных файлов

Снимок зафиксирован перед пробами. После проверок все 27 файлов рабочего проекта совпали с ним.

```json
{
  "Package.swift": "e9ba246f4e2a242318c79d438567f2197001beb23079ec1d67b5e97f39785995",
  "Scripts/build-app-bundle.sh": "7f60e216d64b2c3e6b95375a1047b875a4a63232f3f37a855f7f6db07b0c06e6",
  "Sources/AudoCaptureApp/AppDelegate.swift": "5b0fbacbcfa1c62e81670e5de29f5b83b9bbbc962d3f717d253a40a2d384966f",
  "Sources/AudoCaptureApp/ApplicationModel.swift": "2a487f014dc5fad2640f7d7d1b1db33aedf7f3a875bf8bfe984b6c65740aa67c",
  "Sources/AudoCaptureApp/AudoCaptureApp.swift": "646c7f501ffd8dc197b35b038f0117dae4f575ddf442619d4f4686107a3d3171",
  "Sources/AudoCaptureApp/ContentView.swift": "3b17ed94e1a739989826ab768ed3da2f08f886c17fc6344b848fba1b6eac0113",
  "Sources/AudoCaptureCore/Capture/AudioConversion.swift": "d6f32e92728e5994db031bcf89f97ec127f5f1412fa4ac1a35f44bf0ce5369ac",
  "Sources/AudoCaptureCore/Capture/MicrophoneCaptureService.swift": "6330cb356958954e54d1e278d3fb3f08592e47b3b7d7586113a129c8b1cb22e9",
  "Sources/AudoCaptureCore/Capture/MicrophoneDeviceCatalog.swift": "28ad55ef0f2215bf3af3613f5b26c48388be3c3a0595a37996ea8743b252bc31",
  "Sources/AudoCaptureCore/Capture/SystemAudioCaptureService.swift": "aab2f0371c4f925d29007dd4b7eeffcb468f8f28b842a9f92376ddc31019bdd5",
  "Sources/AudoCaptureCore/Encoding/MP3Encoding.swift": "42df8aaae4f6ddd31fac2668c36045054adcc611bab886d8328677ae53656c12",
  "Sources/AudoCaptureCore/Logging/AppLogger.swift": "0f8687c9a24b6b6e5fdbf2eaff8adb01fcf58c00d13fe684d25af75a32ca7b70",
  "Sources/AudoCaptureCore/Metadata/MetadataWriter.swift": "6830c0418b48cfe7f26698c37bb03b111d2be289af6f24920e15d72d6e604d47",
  "Sources/AudoCaptureCore/Models/RecordingModels.swift": "d26d54cf234cfcd7e42fa86a8af54a841e4e2afdd61bc2a44bc0c615017e82e6",
  "Sources/AudoCaptureCore/Permissions/PermissionsManager.swift": "7678b886618a06a197ccf6b8ebe439f659d2f00ace2ce1b9442da5fe047eb4e9",
  "Sources/AudoCaptureCore/Persistence/PCMFileWriter.swift": "d889cf891fe58e5f5c71c1b75a22d099d3f3d2cba6b09fbce4cf62fe45ce04ad",
  "Sources/AudoCaptureCore/Persistence/RecordingDirectoryManager.swift": "3a1231e1cc4a48a8afeac841f264a3e099ee8bed3f8e885cffdf741e9b4eebf4",
  "Sources/AudoCaptureCore/Recording/AudioSyncCoordinator.swift": "d61e3b0d36bfd745d57f296382b9c0a137b2189f894f093edf018fdbae74c877",
  "Sources/AudoCaptureCore/Recording/RecordingDependencies.swift": "09a36c3ce00b6278fc149642136d86f476c0e2dd87890906168b0e54296dd32a",
  "Sources/AudoCaptureCore/Recording/RecordingManager.swift": "7c4a5b54c0bb422d50582c8abd2a7626b4e39d608f0a758df09043fd8672dd40",
  "Sources/AudoCaptureCore/Recording/RecordingViewModel.swift": "200bc9db1b8f6454aff204ccaa2069c9a61657573722a89eee3896d867097e1b",
  "Sources/AudoCaptureSmokeChecks/main.swift": "e4bf9b39c7f9cf8083d48227c46894731959507f8fd69f23328833b187a1834f",
  "Tests/AudoCaptureCoreTests/AudioSyncCoordinatorTests.swift": "31bba7ba6ba4f638bd3eb2d06418165ec95a71fd52c74cd02d2eebfbb1b30374",
  "Tests/AudoCaptureCoreTests/MetadataWriterTests.swift": "6b1afa3426d7af1164bcfe2d34ac04d3bbf18bdce3a2c40e842cf63502113618",
  "Tests/AudoCaptureCoreTests/RecordingDirectoryManagerTests.swift": "016a5840ea9ea278bdda053ce7f16a418c228201a857477db363c68ffc8b5e12",
  "Tests/AudoCaptureCoreTests/RecordingManagerTests.swift": "aaa1cc3bc7f4814fd5fe84e1ef407ed315890e80231909924b60f914435754a7",
  "Tests/AudoCaptureCoreTests/RecordingViewModelTests.swift": "7cc5ea5ba03b37b2bc660ea63e5b86aa665d065b76e778fb3b6b20aec61df1c9"
}
```
