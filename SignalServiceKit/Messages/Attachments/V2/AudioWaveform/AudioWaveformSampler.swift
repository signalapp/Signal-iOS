//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import Foundation

/// Responsible for ingesting audio samples and producing an `AudioWaveform`.
class AudioWaveformSampler {
    private let inputCount: Int
    private let outputCount: Int

    /// The number of input samples that feed each output sample (rounded up).
    /// The last segment may be shorter.
    private let segmentLength: Int

    /// The number of samples remaining in this segment.
    private var currentSegmentRemainingCount: Int

    /// Tracks the cumulative average when a segment spans multiple batches.
    private var currentSegmentAverage: Float

    private var buffer = [Float]()
    private var output = [UInt8]()

    /// Construct an `AudioWaveformSampler` for ingesting `inputCount` samples,
    /// and producing an `AudioWaveform` with at most `outputCount` bars.
    init(inputCount: Int, outputCount: Int) {
        self.inputCount = inputCount
        self.outputCount = outputCount
        if inputCount < outputCount {
            // If we don't have enough samples, just use every sample that's provided.
            // This will result in fewer than outputCount samples, but that is fine.
            self.segmentLength = 1
        } else {
            let (quotient, remainder) = inputCount.quotientAndRemainder(dividingBy: outputCount)
            self.segmentLength = remainder > 0 ? quotient + 1 : quotient
        }
        self.currentSegmentAverage = 0
        self.currentSegmentRemainingCount = self.segmentLength
    }

    /// Whether every output sample has been produced. Further calls to
    /// `update` can't change the result of `finalize`.
    var isComplete: Bool {
        return self.output.count >= self.outputCount
    }

    /// Update the sampler by ingesting the given 16-bit samples.
    func update(_ samples: UnsafeBufferPointer<Int16>) {
        let sampleCount = samples.count
        self.growBuffer(toCount: sampleCount)

        // convert UInt16 amplitudes to Float representation
        vDSP_vflt16(samples.baseAddress!, 1, &self.buffer, 1, vDSP_Length(sampleCount))

        // normalize into [-1, 1]
        var scale = 1 / -Float(Int16.min)
        vDSP_vsmul(self.buffer, 1, &scale, &self.buffer, 1, vDSP_Length(sampleCount))

        // square, so we average the mean square of each segment
        vDSP_vsq(self.buffer, 1, &self.buffer, 1, vDSP_Length(sampleCount))

        self.reduce(sampleCount: sampleCount)
    }

#if TESTABLE_BUILD
    /// Update the sampler by ingesting the given normalized samples in the
    /// range [-1, 1].
    func update(normalizedSamples samples: UnsafeBufferPointer<Float>) {
        let sampleCount = samples.count
        self.growBuffer(toCount: sampleCount)

        vDSP_vsq(samples.baseAddress!, 1, &self.buffer, 1, vDSP_Length(sampleCount))

        self.reduce(sampleCount: sampleCount)
    }
#endif

    private func growBuffer(toCount count: Int) {
        if self.buffer.count < count {
            self.buffer.append(contentsOf: Array(repeating: 0, count: count - self.buffer.count))
        }
    }

    private func reduce(sampleCount: Int) {
        self.buffer.withUnsafeBufferPointer { bufferPtr in
            var remainingCount = sampleCount
            // If a file understates its sample count in its container metadata,
            // we'll be using a too-short segment length and consequently could
            // take more samples than we expect. Short-circuit if we've already
            // taken all the samples we intend to.
            while
                remainingCount > 0,
                !self.isComplete
            {
                let chunkCount = min(remainingCount, self.currentSegmentRemainingCount)
                assert(chunkCount > 0) // because currentSegmentRemainingCount starts > 0 and is checked on each iteration
                var chunkAverage: Float = 0
                vDSP_meanv(bufferPtr.baseAddress!.advanced(by: sampleCount - remainingCount), 1, &chunkAverage, vDSP_Length(chunkCount))
                remainingCount -= chunkCount
                self.currentSegmentRemainingCount -= chunkCount

                // Add the new average to the running average for this segment.
                let totalChunkCount = self.segmentLength - self.currentSegmentRemainingCount
                assert(totalChunkCount > 0) // because chunkCount > 0
                let newChunkWeight = Float(chunkCount) / Float(totalChunkCount)
                let oldChunkWeight = 1 - newChunkWeight
                self.currentSegmentAverage *= oldChunkWeight
                self.currentSegmentAverage += chunkAverage * newChunkWeight

                // If we reached the end of the chunk, add it to the output.
                if self.currentSegmentRemainingCount <= 0 {
                    self.finishSegment()
                }
            }
        }
    }

    /// Finalize the sampler, producing an `AudioWaveform` from the ingested
    /// samples.
    func finalizeWaveform() throws -> AudioWaveform {
        // Flush the last segment, which may be short.
        if self.currentSegmentRemainingCount < self.segmentLength, !self.isComplete {
            self.finishSegment()
        }
        owsAssertDebug(self.output.count <= self.outputCount)

        do {
            return try AudioWaveform(waveformData: Data(self.output))
        } catch {
            owsFailDebug("How did we sample such that we produced an invalid waveform? \(error)")
            throw error
        }
    }

    private func finishSegment() {
        self.output.append(Self.waveformByte(meanSquare: self.currentSegmentAverage))
        self.currentSegmentAverage = 0 // technically redundant
        self.currentSegmentRemainingCount = self.segmentLength
    }

    /// Anything below this decibel level is considered silent.
    private static let noiseFloor: Float = -60

    private static func waveformByte(meanSquare: Float) -> UInt8 {
        let decibels = 10 * log10(meanSquare)
        let level = min(1, max(0, decibels - noiseFloor) / -noiseFloor)
        return UInt8((Float(UInt8.max) * level).rounded())
    }
}
