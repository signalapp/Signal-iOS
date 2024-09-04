//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import AVFoundation
import Foundation

extension TSAttachmentMigration {

    struct AudioWaveform {
        let decibelSamples: [Float]

        func archive() throws -> Data {
            return try NSKeyedArchiver.archivedData(withRootObject: decibelSamples, requiringSecureCoding: false)
        }
    }

    class AudioWaveformManager {

        static func buildAudioWaveForm(
            unencryptedFilePath: String
        ) throws -> TSAttachmentMigration.AudioWaveform {
            let asset: AVAsset = try assetFromUnencryptedAudioFile(atAudioPath: unencryptedFilePath)

            guard asset.isReadable else {
                throw OWSAssertionError("unexpectedly encountered unreadable audio file.")
            }

            guard CMTimeGetSeconds(asset.duration) <= Self.maximumDuration else {
                throw OWSAssertionError("Audio too long")
            }

            return try sampleWaveform(asset: asset)
        }

        private static func assetFromUnencryptedAudioFile(
            atAudioPath audioPath: String
        ) throws -> AVAsset {
            let audioUrl = URL(fileURLWithPath: audioPath)

            var asset = AVURLAsset(url: audioUrl)

            if !asset.isReadable {
                if let extensionOverride = Self.alternativeAudioFileExtension(fileExtension: audioUrl.pathExtension) {
                    let symlinkPath = OWSFileSystem.temporaryFilePath(
                        fileExtension: extensionOverride,
                        isAvailableWhileDeviceLocked: true
                    )
                    do {
                        try FileManager.default.createSymbolicLink(
                            atPath: symlinkPath,
                            withDestinationPath: audioPath
                        )
                    } catch {
                        throw OWSAssertionError("Failed to create symlink")
                    }
                    asset = AVURLAsset(url: URL(fileURLWithPath: symlinkPath))
                }
            }

            return asset
        }

        private static func alternativeAudioFileExtension(fileExtension: String) -> String? {
            // In some cases, Android sends audio messages with the "audio/mpeg" mime type. This
            // makes our choice of file extension ambiguous—`.mp3` or `.m4a`? AVFoundation uses the
            // extension to read the file, and if the extension is wrong, it won't be readable.
            //
            // We "lie" about the extension to generate the waveform so that AVFoundation may read
            // it. This is brittle but necessary to work around the buggy marriage of Android's
            // content type and AVFoundation's behavior.
            //
            // Note that we probably still want this code even if Android updates theirs, because
            // iOS users might have existing attachments.
            //
            // See:
            // <https://github.com/signalapp/Signal-iOS/issues/3590>.
            switch fileExtension {
            case "m4a": return "aac"
            case "mp3": return "m4a"
            default: return nil
            }
        }

        // MARK: - Sampling

        /// The maximum duration asset that we will display waveforms for.
        /// It's too intensive to sample a waveform for really long audio files.
        private static let maximumDuration: TimeInterval = 15 * kMinuteInterval
        private static let sampleCount = 100

        private static func sampleWaveform(asset: AVAsset) throws -> TSAttachmentMigration.AudioWaveform {
            let assetReader = try AVAssetReader(asset: asset)

            // We just draw the waveform based on the first track.
            guard let audioTrack = assetReader.asset.tracks.first else {
                throw OWSAssertionError("audio file has no tracks")
            }

            let trackOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            assetReader.add(trackOutput)

            let decibelSamples = try readDecibels(from: assetReader)

            return TSAttachmentMigration.AudioWaveform(decibelSamples: decibelSamples)
        }

        private static func readDecibels(from assetReader: AVAssetReader) throws -> [Float] {
            let sampler = AudioWaveformSampler(
                inputCount: sampleCount(from: assetReader),
                outputCount: Self.sampleCount
            )

            assetReader.startReading()
            while assetReader.status == .reading {
                guard let trackOutput = assetReader.outputs.first else {
                    throw OWSAssertionError("track output unexpectedly missing")
                }

                // Process any newly read data.
                guard
                    let nextSampleBuffer = trackOutput.copyNextSampleBuffer(),
                    let blockBuffer = CMSampleBufferGetDataBuffer(nextSampleBuffer)
                else {
                    // There is no more data to read, break
                    break
                }

                var lengthAtOffset = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let result = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: &lengthAtOffset,
                    totalLengthOut: nil,
                    dataPointerOut: &dataPointer
                )
                guard result == kCMBlockBufferNoErr else {
                    owsFailDebug("track data unexpectedly inaccessible")
                    throw AudioWaveformError.invalidAudioFile
                }
                let bufferPointer = UnsafeBufferPointer(start: dataPointer, count: lengthAtOffset)
                bufferPointer.withMemoryRebound(to: Int16.self) { sampler.update($0) }
                CMSampleBufferInvalidate(nextSampleBuffer)
            }

            return sampler.finalize()
        }

        private static func sampleCount(from assetReader: AVAssetReader) -> Int {
            let samplesPerChannel = Int(assetReader.asset.duration.value)

            // We will read in the samples from each channel, interleaved since
            // we only draw one waveform. This gives us an average of the channels
            // if it is, for example, a stereo audio file.
            return samplesPerChannel * channelCount(from: assetReader)
        }

        private static func channelCount(from assetReader: AVAssetReader) -> Int {
            guard
                let output = assetReader.outputs.first as? AVAssetReaderTrackOutput,
                let formatDescriptions = output.track.formatDescriptions as? [CMFormatDescription]
            else {
                return 0
            }

            var channelCount = 0

            for description in formatDescriptions {
                guard let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
                    continue
                }
                channelCount = Int(basicDescription.pointee.mChannelsPerFrame)
            }

            return channelCount
        }
    }

    private class AudioWaveformSampler {
        private static let silenceThreshold: Float = -50

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
            var quietestClipValue = AudioWaveformSampler.silenceThreshold
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
}
