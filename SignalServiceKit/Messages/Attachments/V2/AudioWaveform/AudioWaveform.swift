//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import Foundation

public class AudioWaveform: Equatable {

    /// The recorded samples for this waveform.
    private let decibelSamples: [Float]

    public init(decibelSamples: [Float]) {
        self.decibelSamples = decibelSamples
    }

    public static func == (lhs: AudioWaveform, rhs: AudioWaveform) -> Bool {
        lhs.decibelSamples == rhs.decibelSamples
    }

    // MARK: - Caching

    public init(archivedData: Data) throws {
        let unarchivedSamples = try NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: NSNumber.self, from: archivedData)
        guard let unarchivedSamples else {
            throw OWSAssertionError("Failed to unarchive decibel samples")
        }
        decibelSamples = unarchivedSamples.map { $0.floatValue }
    }

    public func archive() throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: decibelSamples, requiringSecureCoding: false)
    }

    public func write(toFile filePath: String, atomically: Bool) throws {
        let archivedData = try NSKeyedArchiver.archivedData(withRootObject: decibelSamples, requiringSecureCoding: false)
        try archivedData.write(to: URL(fileURLWithPath: filePath), options: atomically ? .atomicWrite : .init())
    }

    // MARK: -

    public func normalizedLevelsToDisplay(sampleCount: Int) -> [Float] {
        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        // Normalize to a range of 0-1 with 0 being silence and
        // 1 being the loudest value we render.
        func normalize(_ float: Float) -> Float {
            float.inverseLerp(
                AudioWaveform.silenceThreshold,
                AudioWaveform.clippingThreshold,
                shouldClamp: true
            )
        }

        // If we're trying to downsample to more samples than exist, just return what we have.
        guard decibelSamples.count > sampleCount else {
            return decibelSamples.map(normalize)
        }

        let downSampledData = Self.downsample(samples: decibelSamples, toSampleCount: sampleCount)

        return downSampledData.map(normalize)
    }

    static func downsample(samples: [Float], toSampleCount sampleCount: Int) -> [Float] {
        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        // Calculate the number of samples each resulting sample should span.
        // If samples.count % sampleCount is > 0, that many samples will
        // be omitted from the resulting array. This is okay, because we don't
        // remove any unprocessed samples from the read buffer and will include
        // them in the next group to downsample.
        let strideLength = samples.count / sampleCount

        // This filter indicates that we should evaluate each sample equally when downsampling.
        let filter = [Float](repeating: 1.0 / Float(strideLength), count: strideLength)
        var downSampledData = [Float](repeating: 0.0, count: sampleCount)

        vDSP_desamp(
            samples,
            vDSP_Stride(strideLength),
            filter,
            &downSampledData,
            vDSP_Length(sampleCount),
            vDSP_Length(strideLength)
        )

        return downSampledData
    }

    // MARK: - Constants

    /// Anything below this decibel level is considered silent and clipped.
    static let silenceThreshold: Float = -50
    static let clippingThreshold: Float = -20

    /// The number of samples to collect for the given audio file.
    /// We limit this to restrict the memory space an individual audio
    /// file can consume.
    ///
    /// If rendering waveforms at a higher resolution, this value may
    /// need to be adjusted appropriately.
    ///
    /// Currently, these samples are cached to disk, so we need to
    /// make sure that sample count produces a reasonably file size.
    static let sampleCount = 100
}
