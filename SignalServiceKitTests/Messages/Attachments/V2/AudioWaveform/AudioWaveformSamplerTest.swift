//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
import XCTest

@testable import SignalServiceKit

final class AudioWaveformSamplerTest: XCTestCase {
    func testCorrectness() {
        let sampler = AudioWaveformSampler(inputCount: 8, outputCount: 3)
        sampler.update([4_000, 8_000, 12_000, 16_000])
        sampler.update([20_000, 24_000, 28_000, 32_000])
        let result = sampler.finalize()
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], 206)
        XCTAssertEqual(result[1], 237)
        XCTAssertEqual(result[2], 252)
    }

    func testOverflow() {
        do {
            let sampler = AudioWaveformSampler(inputCount: 11, outputCount: 10)
            sampler.update([32_767] + Array(repeating: 0, count: 9) + [32_767])
            let result = sampler.finalize()
            XCTAssertEqual(result.count, 6)
            XCTAssertEqual(result.first!, 242)
            XCTAssertEqual(result.last!, 255)
        }
        do {
            let sampler = AudioWaveformSampler(inputCount: 19, outputCount: 10)
            sampler.update([32_767] + Array(repeating: 0, count: 17) + [32_767])
            let result = sampler.finalize()
            XCTAssertEqual(result.count, 10)
            XCTAssertEqual(result.first!, 242)
            XCTAssertEqual(result.last!, 255)
        }
    }

    func testTooFewSamples() {
        let sampler = AudioWaveformSampler(inputCount: 5, outputCount: 10)
        sampler.update(Array(repeating: 0, count: 5))
        XCTAssertEqual(sampler.finalize().count, 5)
    }

    /// `inputCount` comes from container metadata that may understate how many
    /// samples will actually arrive. The output must stay bounded by
    /// `outputCount` no matter how many samples arrive.
    func testUnderstatedInputCountIsBounded() {
        struct TestCase {
            let inputCount: Int
            let outputCount: Int
            let actualInputSamples: Int
        }

        let testCases: [TestCase] = [
            TestCase(inputCount: 0, outputCount: 10, actualInputSamples: 10_000),
            TestCase(inputCount: 11, outputCount: 10, actualInputSamples: 10_000),
            TestCase(inputCount: 100, outputCount: 10, actualInputSamples: 10_000),
        ]

        for testCase in testCases {
            let sampler = AudioWaveformSampler(inputCount: testCase.inputCount, outputCount: testCase.outputCount)
            sampler.update(Array(repeating: 0, count: testCase.actualInputSamples))
            XCTAssertEqual(sampler.finalize().count, testCase.outputCount)
        }
    }
}

private extension AudioWaveformSampler {
    func finalize() -> [UInt8] {
        let waveform = try! self.finalizeWaveform()
        return [UInt8](waveform.waveformData)
    }

    func update(_ samples: [Int16]) {
        samples.withUnsafeBufferPointer(self.update)
    }

    func update(normalizedSamples samples: [Float]) {
        samples.withUnsafeBufferPointer { self.update(normalizedSamples: $0) }
    }
}

// MARK: -

struct AudioWaveformSamplerSpecTest {

    @Test(arguments: [
        ([0.1, -0.2, 0.3, -0.4, 0.5, -0.6], 3, [187, 217, 233]),
        ([-0.1, 0.2, -0.3, 0.4, -0.5, 0.6, -0.7, 0.8], 3, [198, 230, 244]),
    ] as [(samples: [Float], waveformLength: Int, expected: [UInt8])])
    func specVectors(testCase: (samples: [Float], waveformLength: Int, expected: [UInt8])) {
        // Feed the samples all at once, and one at a time, to exercise
        // segments that span multiple batches.
        let batchings = [[testCase.samples], testCase.samples.map { [$0] }]
        for batches in batchings {
            let sampler = AudioWaveformSampler(
                inputCount: testCase.samples.count,
                outputCount: testCase.waveformLength,
            )
            for batch in batches {
                sampler.update(normalizedSamples: batch)
            }
            #expect(sampler.finalize() == testCase.expected)
        }
    }

    @Test
    func int16Normalization() {
        let sampler = AudioWaveformSampler(inputCount: 4, outputCount: 4)
        sampler.update([Int16.min, Int16.max, 16_384, 0])
        #expect(sampler.finalize() == [255, 255, 229, 0])
    }
}
