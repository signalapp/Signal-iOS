//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct AudioWaveformTest {

    @Test
    func waveformDataRoundTrip() throws {
        let allBytes = Array(UInt8.min...UInt8.max)
        for start in stride(from: 0, to: allBytes.count, by: AudioWaveform.sampleCount) {
            let end = min(start + AudioWaveform.sampleCount, allBytes.count)
            let waveformData = Data(allBytes[start..<end])
            #expect(try AudioWaveform(waveformData: waveformData).waveformData == waveformData)
        }
    }

    @Test(arguments: [1, AudioWaveform.sampleCount])
    func acceptsValidSampleCounts(sampleCount: Int) throws {
        let waveformData = Data(repeating: 128, count: sampleCount)
        #expect(try AudioWaveform(waveformData: waveformData).waveformData == waveformData)
        _ = try AudioWaveform(levels: Array(repeating: 0.5, count: sampleCount))
        _ = try AudioWaveform(archivedData: archivedDecibels(count: sampleCount))
    }

    /// Past sampler bugs could produce a couple more samples than allowed.
    @Test(arguments: [0, AudioWaveform.sampleCount + 1, AudioWaveform.sampleCount + 2])
    func rejectsInvalidSampleCounts(sampleCount: Int) throws {
        #expect(throws: (any Error).self) {
            try AudioWaveform(waveformData: Data(repeating: 128, count: sampleCount))
        }
        #expect(throws: (any Error).self) {
            try AudioWaveform(levels: Array(repeating: 0.5, count: sampleCount))
        }
        let archivedData = try archivedDecibels(count: sampleCount)
        #expect(throws: (any Error).self) {
            try AudioWaveform(archivedData: archivedData)
        }
    }

    @Test(arguments: [
        (-60, 0),
        (AudioWaveform.silenceThreshold, 0),
        (-35, 128),
        (AudioWaveform.clippingThreshold, 255),
        (0, 255),
    ] as [(decibels: Float, expectedByte: UInt8)])
    func decibelsToBarHeights(testCase: (decibels: Float, expectedByte: UInt8)) throws {
        let level = AudioWaveform.level(fromDecibels: testCase.decibels)
        let waveform = try AudioWaveform(levels: [level])
        #expect(waveform.waveformData == Data([testCase.expectedByte]))
    }

    // MARK: -

    private func archivedDecibels(count: Int) throws -> Data {
        let decibels = Array(repeating: NSNumber(value: Float(-35)), count: count)
        return try NSKeyedArchiver.archivedData(
            withRootObject: decibels,
            requiringSecureCoding: true,
        )
    }
}
