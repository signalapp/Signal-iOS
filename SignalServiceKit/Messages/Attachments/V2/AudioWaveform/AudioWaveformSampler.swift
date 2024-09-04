//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import Foundation

class AudioWaveformSampler {
    private let inputCount: Int
    private let outputCount: Int

    /// The number of input samples that feed each output sample (rounded down).
    private let segmentLength: Int

    /// The number of samples that don't evenly divide into `outputCount`. These
    /// extra samples are spread across the output samples.
    private let segmentRemainder: Int

    /// The number of samples in this segment. Either `segmentLength` or
    /// `segmentLength + 1`.
    private var currentSegmentCount: Int

    /// The number of samples remaining in this segment.
    private var currentSegmentRemainingCount: Int

    /// Tracks the cumulative average when a segment spans multiple batches.
    private var currentSegmentAverage: Float

    /// Tracks when a segment needs an extra sample (because outputCount may not
    /// evenly divide inputCount).
    private var overflowCounter: Int

    private var buffer = [Float]()
    private var output = [Float]()

    init(inputCount: Int, outputCount: Int) {
        self.inputCount = inputCount
        self.outputCount = outputCount
        if inputCount < outputCount {
            // If we don't have enough samples, just use every sample that's provided.
            // This will result in fewer than outputCount samples, but that is fine.
            (self.segmentLength, self.segmentRemainder) = (1, 0)
        } else {
            (self.segmentLength, self.segmentRemainder) = inputCount.quotientAndRemainder(dividingBy: outputCount)
        }
        self.currentSegmentAverage = 0
        // The first segment is always segmentLength because segmentRemainder is
        // less than outputCount (it's the remainder when dividing by outputCount).
        self.currentSegmentCount = self.segmentLength
        self.currentSegmentRemainingCount = self.segmentLength
        self.overflowCounter = self.outputCount - self.segmentRemainder
    }

    func update(_ samples: UnsafeBufferPointer<Int16>) {
        let sampleCount = samples.count
        if self.buffer.count < sampleCount {
            self.buffer.append(contentsOf: Array(repeating: 0, count: sampleCount - self.buffer.count))
        }

        // convert UInt16 amplitudes to Float representation
        vDSP_vflt16(samples.baseAddress!, 1, &self.buffer, 1, vDSP_Length(sampleCount))

        // take the absolute amplitude value
        vDSP_vabs(self.buffer, 1, &self.buffer, 1, vDSP_Length(sampleCount))

        // convert to dB
        // maximum amplitude storable in Int16 = 0 dB (loudest)
        // (remember decibels are often negative)
        var zeroDecibelEquivalent: Float = Float(Int16.max)
        vDSP_vdbcon(self.buffer, 1, &zeroDecibelEquivalent, &self.buffer, 1, vDSP_Length(sampleCount), 1)

        // clip between loudest + quietest
        var loudestClipValue: Float = 0.0
        var quietestClipValue = AudioWaveform.silenceThreshold
        vDSP_vclip(self.buffer, 1, &quietestClipValue, &loudestClipValue, &self.buffer, 1, vDSP_Length(sampleCount))

        self.reduce(sampleCount: sampleCount)
    }

    private func reduce(sampleCount: Int) {
        self.buffer.withUnsafeBufferPointer { bufferPtr in
            var remainingCount = sampleCount
            while remainingCount > 0 {
                let chunkCount = min(remainingCount, self.currentSegmentRemainingCount)
                assert(chunkCount > 0)  // because currentSegmentRemainingCount starts > 0 and is checked on each iteration
                var chunkAverage: Float = 0
                vDSP_meanv(bufferPtr.baseAddress!.advanced(by: sampleCount - remainingCount), 1, &chunkAverage, vDSP_Length(chunkCount))
                remainingCount -= chunkCount
                self.currentSegmentRemainingCount -= chunkCount

                // Add the new average to the running average for this segment.
                let totalChunkCount = self.currentSegmentCount - self.currentSegmentRemainingCount
                assert(totalChunkCount > 0)  // because chunkCount > 0
                let newChunkWeight = Float(chunkCount) / Float(totalChunkCount)
                let oldChunkWeight = 1 - newChunkWeight
                self.currentSegmentAverage *= oldChunkWeight
                self.currentSegmentAverage += chunkAverage * newChunkWeight

                // If we reached the end of the chunk, add it to the output.
                if self.currentSegmentRemainingCount <= 0 {
                    self.output.append(self.currentSegmentAverage)
                    self.currentSegmentAverage = 0  // technically redundant

                    self.currentSegmentCount = self.segmentLength
                    self.overflowCounter -= self.segmentRemainder
                    if self.overflowCounter <= 0 {
                        self.currentSegmentCount += 1
                        self.overflowCounter += self.segmentLength
                    }
                    self.currentSegmentRemainingCount = self.currentSegmentCount
                }
            }
        }
    }

    func finalize() -> [Float] {
        assert(self.output.count <= self.outputCount)
        return self.output
    }
}
