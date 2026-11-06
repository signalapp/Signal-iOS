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
    func takesSenderProvidedDetails() throws {
        let waveformSamples = Data(repeating: 128, count: AudioWaveform.sampleCount)

        #expect(
            audioDetails(waveformSamples: waveformSamples, durationSeconds: 12.5)
                == Attachment.AudioDetails(
                    duration: 12.5,
                    waveform: try AudioWaveform(waveformData: waveformSamples),
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
                    waveform: nil,
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
                    waveform: nil,
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

    // MARK: -

    private func audioDetails(
        waveformSamples: Data? = nil,
        durationSeconds: Float? = nil,
    ) -> Attachment.AudioDetails? {
        let builder = SSKProtoAttachmentPointer.builder()
        waveformSamples.map(builder.setAudioWaveform(_:))
        durationSeconds.map(builder.setAudioDurationSeconds(_:))

        return Attachment.AudioDetails(
            pointerProto: builder.buildInfallibly(),
        )
    }
}
