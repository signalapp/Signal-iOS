//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import Foundation

public class AudioWaveform: Equatable {

    private enum Samples: Equatable {
        /// Decibel values, which must be normalized before display.
        case decibels([Float])
        /// Display levels from 0 to 1, ready to display as-is.
        case levels([Float])
    }

    /// The recorded samples for this waveform.
    private let samples: Samples

    public init(decibelSamples: [Float]) {
        self.samples = .decibels(decibelSamples)
    }

    /// Create a waveform from its serialized representation: one byte per
    /// sample, each a bar height from 0 (silence) to `UInt8.max` (the loudest
    /// bar we draw).
    public init(waveformData: Data) {
        self.samples = .levels(waveformData.map { Self.level(fromByte: $0) })
    }

    /// This waveform serialized as one byte per sample; see
    /// ``init(waveformData:)``.
    public var waveformData: Data {
        let levels: [Float] = switch samples {
        case .decibels(let decibelSamples): decibelSamples.map(Self.normalize(_:))
        case .levels(let levels): levels
        }
        return Data(levels.map(Self.byte(fromLevel:)))
    }

    public static func ==(lhs: AudioWaveform, rhs: AudioWaveform) -> Bool {
        lhs.samples == rhs.samples
    }

    // MARK: - Caching

    public init(archivedData: Data) throws {
        let unarchivedSamples = try NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: NSNumber.self, from: archivedData)
        guard let unarchivedSamples else {
            throw OWSAssertionError("Failed to unarchive decibel samples")
        }
        samples = .decibels(unarchivedSamples.map { $0.floatValue })
    }

    public func archive() throws -> Data {
        switch samples {
        case .decibels(let decibelSamples):
            return try NSKeyedArchiver.archivedData(withRootObject: decibelSamples, requiringSecureCoding: true)
        case .levels:
            throw OWSAssertionError("Archiving a waveform without decibel samples!")
        }
    }

    public func write(toFile filePath: String, atomically: Bool) throws {
        try archive().write(to: URL(fileURLWithPath: filePath), options: atomically ? .atomicWrite : .init())
    }

    // MARK: -

    public func normalizedLevelsToDisplay(sampleCount: Int) -> [Float] {
        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        switch samples {
        case .decibels(let decibelSamples):
            // If we're trying to downsample to more samples than exist, just return what we have.
            guard decibelSamples.count > sampleCount else {
                return decibelSamples.map(Self.normalize(_:))
            }
            return Self
                .downsample(samples: decibelSamples, toSampleCount: sampleCount)
                .map(Self.normalize(_:))
        case .levels(let levels):
            guard levels.count > sampleCount else {
                return levels
            }
            return Self.downsample(samples: levels, toSampleCount: sampleCount)
        }
    }

    /// Normalize a decibel value to a range of 0-1, with 0 being silence and 1
    /// being the loudest value we render.
    private static func normalize(_ decibels: Float) -> Float {
        decibels.inverseLerp(
            AudioWaveform.silenceThreshold,
            AudioWaveform.clippingThreshold,
            shouldClamp: true,
        )
    }

    private static func level(fromByte byte: UInt8) -> Float {
        Float(byte) / Float(UInt8.max)
    }

    private static func byte(fromLevel level: Float) -> UInt8 {
        guard level.isFinite else { return 0 }
        return UInt8(clamping: Int((level * Float(UInt8.max)).rounded()))
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
            vDSP_Length(strideLength),
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
    /// Samples are stored and sent one byte apiece, so this is also the
    /// maximum size of a serialized waveform.
    public static let sampleCount = 100
}
