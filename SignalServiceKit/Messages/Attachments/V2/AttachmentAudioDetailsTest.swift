//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

/// Tests `Attachment/AudioDetails` as built from an incoming `AttachmentPointer`.
struct AttachmentAudioDetailsFromProtoTest {

    @Test
    func takesSenderProvidedDetails() {
        let waveformSamples = Data(repeating: 128, count: AudioWaveform.sampleCount)

        #expect(
            audioDetails(waveformSamples: waveformSamples, durationSeconds: 12.5)
                == Attachment.AudioDetails(
                    duration: 12.5,
                    waveformSamples: waveformSamples,
                    waveformRelativeFilePath: nil,
                ),
        )
    }

    @Test
    func takesDurationWithoutWaveform() {
        #expect(
            audioDetails(durationSeconds: 12.5)
                == Attachment.AudioDetails(
                    duration: 12.5,
                    waveformSamples: nil,
                    waveformRelativeFilePath: nil,
                ),
        )
    }

    /// A waveform longer than the format allows means the sender disagrees
    /// with us about the format, so we take the duration and drop the samples.
    @Test(arguments: [
        Data(repeating: 128, count: AudioWaveform.sampleCount + 1),
        Data(),
    ])
    func dropsUnusableWaveforms(waveformSamples: Data) {
        #expect(
            audioDetails(waveformSamples: waveformSamples, durationSeconds: 12.5)
                == Attachment.AudioDetails(
                    duration: 12.5,
                    waveformSamples: nil,
                    waveformRelativeFilePath: nil,
                ),
        )
    }

    /// Details are keyed on the duration, so a waveform without one is
    /// dropped along with it.
    @Test(arguments: [nil, 0, -1, .nan, .infinity] as [Float?])
    func dropsDetailsWithoutUsableDuration(durationSeconds: Float?) {
        let waveformSamples = Data(repeating: 128, count: AudioWaveform.sampleCount)

        #expect(audioDetails(waveformSamples: waveformSamples, durationSeconds: durationSeconds) == nil)
    }

    @Test
    func dropsDetailsForOtherContentTypes() {
        let waveformSamples = Data(repeating: 128, count: AudioWaveform.sampleCount)

        // Not parameterized: `ContentType` isn't `Sendable` outside its module.
        for contentType in [Attachment.ContentType.file, .image, .video] {
            #expect(
                audioDetails(
                    waveformSamples: waveformSamples,
                    durationSeconds: 12.5,
                    contentType: contentType,
                ) == nil,
                "\(contentType)",
            )
        }
    }

    // MARK: -

    private func audioDetails(
        waveformSamples: Data? = nil,
        durationSeconds: Float? = nil,
        contentType: Attachment.ContentType = .audio,
    ) -> Attachment.AudioDetails? {
        let builder = SSKProtoAttachmentPointer.builder()
        waveformSamples.map(builder.setAudioWaveform(_:))
        durationSeconds.map(builder.setAudioDurationSeconds(_:))

        return Attachment.AudioDetails(
            pointerProto: builder.buildInfallibly(),
            contentType: contentType,
        )
    }
}
