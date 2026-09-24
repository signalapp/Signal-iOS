//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct AudioWaveformTest {

    @Test
    func waveformDataRoundTrip() {
        let waveformData = Data(UInt8.min...UInt8.max)
        #expect(AudioWaveform(waveformData: waveformData).waveformData == waveformData)
    }

    @Test
    func emptyWaveformData() {
        let waveform = AudioWaveform(waveformData: Data())
        #expect(waveform.waveformData == Data())
        #expect(waveform.normalizedLevelsToDisplay(sampleCount: 50) == [])
    }

    @Test(arguments: [
        (-60, 0),
        (AudioWaveform.silenceThreshold, 0),
        (-35, 128),
        (AudioWaveform.clippingThreshold, 255),
        (0, 255),
    ] as [(decibels: Float, expectedByte: UInt8)])
    func decibelsToBarHeights(testCase: (decibels: Float, expectedByte: UInt8)) {
        let level = AudioWaveform.level(fromDecibels: testCase.decibels)
        let waveform = AudioWaveform(levels: [level])
        #expect(waveform.waveformData == Data([testCase.expectedByte]))
    }
}
