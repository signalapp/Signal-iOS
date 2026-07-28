//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

final class AudioWaveformSamplerTest: XCTestCase {
    func testCorrectness() {
        let sampler = AudioWaveformSampler(inputCount: 8, outputCount: 3)
        sampler.update([4_000, 8_000, 12_000, 16_000])
        sampler.update([20_000, 24_000, 28_000, 32_000])
        let result = sampler.finalize()
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], -15.257, accuracy: 0.01)
        XCTAssertEqual(result[1], -6.413, accuracy: 0.01)
        XCTAssertEqual(result[2], -1.425, accuracy: 0.01)
    }

    func testOverflow() {
        do {
            let sampler = AudioWaveformSampler(inputCount: 11, outputCount: 10)
            sampler.update([32_767] + Array(repeating: 0, count: 9) + [32_767])
            let result = sampler.finalize()
            XCTAssertEqual(result.count, 10)
            XCTAssertEqual(result.first!, 0, accuracy: 0.01)
            XCTAssertEqual(result.last!, -25, accuracy: 0.01)
        }
        do {
            let sampler = AudioWaveformSampler(inputCount: 19, outputCount: 10)
            sampler.update([32_767] + Array(repeating: 0, count: 17) + [32_767])
            let result = sampler.finalize()
            XCTAssertEqual(result.count, 10)
            XCTAssertEqual(result.first!, 0, accuracy: 0.01)
            XCTAssertEqual(result.last!, -25, accuracy: 0.01)
        }
    }

    func testTooFewSamples() {
        let sampler = AudioWaveformSampler(inputCount: 5, outputCount: 10)
        sampler.update(Array(repeating: 0, count: 5))
        XCTAssertEqual(sampler.finalize().count, 5)
    }

    func testEmpty() {
        let sampler = AudioWaveformSampler(inputCount: 5, outputCount: 10)
        sampler.update([])
        XCTAssertEqual(sampler.finalize().count, 0)
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
    func update(_ samples: [Int16]) {
        samples.withUnsafeBufferPointer(self.update)
    }
}
