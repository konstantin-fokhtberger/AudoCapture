import AVFoundation
import Testing
@testable import AudoCaptureCore

struct AudioConversionTests {
    @Test(arguments: [16_000.0, 44_100.0, 48_000.0, 96_000.0])
    func continuousInputKeepsProducingAudio(sourceSampleRate: Double) throws {
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1))
        let outputFormat = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let converter = try #require(AVAudioConverter(from: inputFormat, to: outputFormat))

        for _ in 0..<20 {
            let input = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 2_048))
            input.frameLength = 2_048
            let samples = try #require(input.floatChannelData?[0])
            for index in 0..<Int(input.frameLength) {
                samples[index] = 0.25
            }

            let output = try AVAudioPCMBuffer.makeCopy(from: input, using: converter, targetFormat: outputFormat)

            // A continuing source must survive more than the first conversion call.
            #expect(output.frameLength > 0)
            #expect(output.format == outputFormat)
            let convertedSamples = try #require(output.int16ChannelData?[0])
            let peak = (0..<Int(output.frameLength)).map { abs(Int(convertedSamples[$0])) }.max() ?? 0
            #expect(peak > 1_000)
        }
    }

    @Test
    func stereoConversionPreservesBothChannelsAcrossBuffers() throws {
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let outputFormat = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 2)
        let converter = try #require(AVAudioConverter(from: inputFormat, to: outputFormat))

        for _ in 0..<6 {
            let input = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 2_048))
            input.frameLength = 2_048
            let channels = try #require(input.floatChannelData)
            for index in 0..<Int(input.frameLength) {
                channels[0][index] = 0.25
                channels[1][index] = -0.25
            }

            let output = try AVAudioPCMBuffer.makeCopy(from: input, using: converter, targetFormat: outputFormat)

            #expect(output.frameLength == input.frameLength)
            let samples = try #require(output.int16ChannelData?[0])
            // The persisted format is interleaved: L, R, L, R.
            for index in 0..<Int(output.frameLength) {
                #expect(samples[index * 2] > 1_000)
                #expect(samples[index * 2 + 1] < -1_000)
            }
        }
    }
}
