//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import AVFoundation
import Foundation

public protocol AudioWaveformSamplingObserver: AnyObject {
    func audioWaveformDidFinishSampling(_ audioWaveform: AudioWaveform)
}

// MARK: -

public class AudioWaveformManagerImpl: AudioWaveformManager {

    private typealias AttachmentId = TSResourceId

    public init() {}

    public func audioWaveform(
        forAttachment attachment: TSResourceStream,
        highPriority: Bool
    ) -> Task<AudioWaveform, Error> {
        switch attachment.concreteStreamType {
        case .legacy(let tsAttachmentStream):
            return _audioWaveform(forAttachment: tsAttachmentStream, highPriority: highPriority)
        case .v2(let attachmentStream):
            switch attachmentStream.info.contentType {
            case .file, .invalid, .image, .video, .animatedImage:
                return Task {
                    throw OWSAssertionError("Invalid attachment type!")
                }
            case .audio(_, let relativeWaveformFilePath):
                guard let relativeWaveformFilePath else {
                    return Task {
                        // We could not generate a waveform at write time; don't retry now.
                        throw AudioWaveformError.invalidAudioFile
                    }
                }
                let encryptionKey = attachmentStream.attachment.encryptionKey
                return Task {
                    let fileURL = AttachmentStream.absoluteAttachmentFileURL(
                        relativeFilePath: relativeWaveformFilePath
                    )
                    // waveform is validated at creation time; no need to revalidate every read.
                    let data = try Cryptography.decryptFileWithoutValidating(
                        at: fileURL,
                        metadata: .init(
                            key: encryptionKey
                        )
                    )
                    return try AudioWaveform(archivedData: data)
                }
            }
        }
    }

    private func _audioWaveform(
        forAttachment attachment: TSAttachmentStream,
        highPriority: Bool
    ) -> Task<AudioWaveform, Error> {
        let attachmentId = attachment.resourceId
        let mimeType = attachment.mimeType
        let audioWaveformPath = attachment.audioWaveformPath
        let originalFilePath = attachment.originalFilePath

        return Task {
            guard MimeTypeUtil.isSupportedAudioMimeType(mimeType) else {
                owsFailDebug("Not audio.")
                throw AudioWaveformError.invalidAudioFile
            }

            guard let audioWaveformPath else {
                owsFailDebug("Missing audioWaveformPath.")
                throw AudioWaveformError.invalidAudioFile
            }

            guard let originalFilePath else {
                owsFailDebug("Missing originalFilePath.")
                throw AudioWaveformError.invalidAudioFile
            }

            return try await self.buildAudioWaveForm(
                source: .unencryptedFile(path: originalFilePath),
                waveformPath: audioWaveformPath,
                identifier: .attachment(attachmentId),
                highPriority: highPriority
            ).value
        }
    }

    public func audioWaveform(
        forAudioPath audioPath: String,
        waveformPath: String
    ) -> Task<AudioWaveform, Error> {
        return buildAudioWaveForm(
            source: .unencryptedFile(path: audioPath),
            waveformPath: waveformPath,
            identifier: .file(UUID()),
            highPriority: false
        )
    }

    public func audioWaveform(
        forEncryptedAudioFileAtPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String,
        outputWaveformPath: String
    ) async throws {
        let task = buildAudioWaveForm(
            source: .encryptedFile(
                path: filePath,
                encryptionKey: encryptionKey,
                plaintextDataLength: plaintextDataLength,
                mimeType: mimeType
            ),
            waveformPath: outputWaveformPath,
            identifier: .file(UUID()),
            highPriority: false
        )
        // Don't need the waveform; its written to disk by now.
        _ = try await task.value
    }

    public func audioWaveformSync(
        forAudioPath audioPath: String
    ) throws -> AudioWaveform {
        return try _buildAudioWaveForm(
            source: .unencryptedFile(path: audioPath),
            waveformPath: nil
        )
    }

    public func audioWaveformSync(
        forEncryptedAudioFileAtPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String
    ) throws -> AudioWaveform {
        return try _buildAudioWaveForm(
            source: .encryptedFile(
                path: filePath,
                encryptionKey: encryptionKey,
                plaintextDataLength: plaintextDataLength,
                mimeType: mimeType
            ),
            waveformPath: nil
        )
    }

    private enum AVAssetSource {
        case unencryptedFile(path: String)
        case encryptedFile(
            path: String,
            encryptionKey: Data,
            plaintextDataLength: UInt32,
            mimeType: String
        )
    }

    private enum WaveformId: Hashable {
        case attachment(TSResourceId)
        case file(UUID)

        var cacheKey: TSResourceId? {
            switch self {
            case .attachment(let id):
                return id
            case .file:
                // We don't cache ad-hoc file results.
                return nil
            }
        }
    }

    /// "High priority" just gets its own queue.
    private let taskQueue = SerialTaskQueue()
    private let highPriorityTaskQueue = SerialTaskQueue()

    private var cache = LRUCache<AttachmentId, Weak<AudioWaveform>>(maxSize: 64)

    private func buildAudioWaveForm(
        source: AVAssetSource,
        waveformPath: String,
        identifier: WaveformId,
        highPriority: Bool
    ) -> Task<AudioWaveform, Error> {
        return Task {
            if
                let cacheKey = identifier.cacheKey,
                let cachedValue = self.cache[cacheKey]?.value
            {
                return cachedValue
            }

            let taskQueue = highPriority ? self.highPriorityTaskQueue : self.taskQueue
            return try await taskQueue.enqueue(operation: {
                let waveform = try self._buildAudioWaveForm(
                    source: source,
                    waveformPath: waveformPath
                )

                identifier.cacheKey.map { self.cache[$0] = Weak(value: waveform) }
                return waveform
            }).value
        }
    }

    private func _buildAudioWaveForm(
        source: AVAssetSource,
        // If non-nil, writes the waveform to this output file.
        waveformPath: String?
    ) throws -> AudioWaveform {
        if let waveformPath {
            if FileManager.default.fileExists(atPath: waveformPath) {
                // We have a cached waveform on disk, read it into memory.
                do {
                    return try AudioWaveform(contentsOfFile: waveformPath)
                } catch {
                    owsFailDebug("Error: \(error)")

                    // Remove the file from disk and create a new one.
                    OWSFileSystem.deleteFileIfExists(waveformPath)
                }
            }
        }

        let asset: AVAsset
        switch source {
        case .unencryptedFile(let path):
            asset = try assetFromUnencryptedAudioFile(atAudioPath: path)
        case let .encryptedFile(path, encryptionKey, plaintextDataLength, mimeType):
            asset = try assetFromEncryptedAudioFile(
                atPath: path,
                encryptionKey: encryptionKey,
                plaintextDataLength: plaintextDataLength,
                mimeType: mimeType
            )
        }

        guard asset.isReadable else {
            owsFailDebug("unexpectedly encountered unreadable audio file.")
            throw AudioWaveformError.invalidAudioFile
        }

        guard CMTimeGetSeconds(asset.duration) <= Self.maximumDuration else {
            throw AudioWaveformError.audioTooLong
        }

        let waveform = try sampleWaveform(asset: asset)

        if let waveformPath {
            do {
                let parentDirectoryPath = (waveformPath as NSString).deletingLastPathComponent
                if OWSFileSystem.ensureDirectoryExists(parentDirectoryPath) {
                    switch source {
                    case .unencryptedFile:
                        try waveform.write(toFile: waveformPath, atomically: true)
                    case .encryptedFile(_, let encryptionKey, _, _):
                        let waveformData = try waveform.archive()
                        let (encryptedWaveform, _) = try Cryptography.encrypt(waveformData, encryptionKey: encryptionKey)
                        try encryptedWaveform.write(to: URL(fileURLWithPath: waveformPath), options: .atomicWrite)
                    }

                } else {
                    owsFailDebug("Could not create parent directory.")
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        return waveform
    }

    private func assetFromUnencryptedAudioFile(
        atAudioPath audioPath: String
    ) throws -> AVAsset {
        let audioUrl = URL(fileURLWithPath: audioPath)

        var asset = AVURLAsset(url: audioUrl)

        if !asset.isReadable {
            if let extensionOverride = MimeTypeUtil.alternativeAudioFileExtension(fileExtension: audioUrl.pathExtension) {
                let symlinkPath = OWSFileSystem.temporaryFilePath(
                    fileExtension: extensionOverride,
                    isAvailableWhileDeviceLocked: true
                )
                do {
                    try FileManager.default.createSymbolicLink(atPath: symlinkPath,
                                                               withDestinationPath: audioPath)
                } catch {
                    owsFailDebug("Failed to create voice memo symlink: \(error)")
                    throw AudioWaveformError.fileIOError
                }
                asset = AVURLAsset(url: URL(fileURLWithPath: symlinkPath))
            }
        }

        return asset
    }

    private func assetFromEncryptedAudioFile(
        atPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String
    ) throws -> AVAsset {
        let audioUrl = URL(fileURLWithPath: filePath)
        return try AVAsset.fromEncryptedFile(
            at: audioUrl,
            encryptionKey: encryptionKey,
            plaintextLength: plaintextDataLength,
            mimeType: mimeType
        )
    }

    // MARK: - Sampling

    /// The maximum duration asset that we will display waveforms for.
    /// It's too intensive to sample a waveform for really long audio files.
    fileprivate static let maximumDuration: TimeInterval = 15 * kMinuteInterval

    private func downsample(samples: [Float], toSampleCount sampleCount: Int) -> [Float] {
        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        // If the requested sample count is equal to the sample count, just return the samples
        guard samples.count != sampleCount else { return samples }

        // Calculate the number of samples each downsampled value should take into account
        let sampleDistribution = Float(samples.count) / Float(sampleCount)

        // Calculate the number of samples we need to factor in when downsampling. Since there
        // is no such thing as a fractional sample, we need to round this up to the nearest Int.
        // When we calculated the distribution later, it will factor in that some of these samples
        // are weighted differently than others in the resulting output.
        let sampleLength = Int(ceil(sampleDistribution))

        // Calculate the weight of each sample in the downsampled group.
        // For whole number `sampleDistribution` the distribution is always
        // equivalent across all of the samples. If the sampleDistribution
        // is _not_ a whole number, we factor the bookending values in
        // relative to remainder proportion
        let distribution: [Float] = {
            let averageProportion = 1 / sampleDistribution

            var array = [Float](repeating: averageProportion, count: sampleLength)

            if samples.count % sampleCount != 0 {
                // Calculate the proportion that the partial sample should be weighted at
                let remainderProportion = (sampleDistribution.truncatingRemainder(dividingBy: 1)) * averageProportion

                // The partial sample is factored into the "bookends" (first and last element of the distribution)
                // by averaging the average distribution and the remainder distribution together.
                // This provides a lightweight "anti-aliasing" effect.
                let bookEndProportions = (averageProportion + remainderProportion) / 2

                array[0] = bookEndProportions
                array[sampleLength - 1] = bookEndProportions
            }

            return array
        }()

        // If we can ever guarantee that `samples.count` is always a multiple of `sampleCount`, we should
        // switch to using the faster `vDSP_desamp`. For now, we can't use it since it only supports the
        // integer stride lengths. This should be okay, since this should only be operating on already
        // downsampled data (~100 points) rather than the original millions of points.
        let result: [Float] = (0..<sampleCount).map { downsampledIndex in
            let sampleStart = Int(floor(Float(downsampledIndex) * sampleDistribution))
            return samples[sampleStart..<sampleStart + sampleLength].enumerated().reduce(0) { result, value in
                return result + distribution[value.offset] * value.element
            }
        }

        return result
    }

    private func sampleWaveform(asset: AVAsset) throws -> AudioWaveform {
        try Task.checkCancellation()

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            owsFailDebug("Unexpectedly failed to initialize asset reader")
            throw AudioWaveformError.fileIOError
        }

        // We just draw the waveform based on the first track.
        guard let audioTrack = assetReader.asset.tracks.first else {
            owsFailDebug("audio file has no tracks")
            throw AudioWaveformError.invalidAudioFile
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

        try Task.checkCancellation()

        return AudioWaveform(decibelSamples: decibelSamples)
    }

    private func readDecibels(from assetReader: AVAssetReader) throws -> [Float] {
        var outputSamples = [Float]()
        var readBuffer = Data()

        let samplesToGroup = max(1, sampleCount(from: assetReader) / AudioWaveform.sampleCount)

        assetReader.startReading()
        while assetReader.status == .reading {
            // Stop reading if the operation is cancelled.
            try Task.checkCancellation()

            guard let trackOutput = assetReader.outputs.first else {
                owsFailDebug("track output unexpectedly missing")
                throw AudioWaveformError.invalidAudioFile
            }

            // Process any newly read data.
            guard let nextSampleBuffer = trackOutput.copyNextSampleBuffer(),
                let blockBuffer = CMSampleBufferGetDataBuffer(nextSampleBuffer) else {
                    // There is no more data to read, break
                    break
            }

            var readBufferLength = 0
            var readBufferPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &readBufferLength,
                totalLengthOut: nil,
                dataPointerOut: &readBufferPointer
            )
            readBuffer.append(UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
            CMSampleBufferInvalidate(nextSampleBuffer)

            // Try and process any pending samples, we may not have read enough data yet to do this.
            let processedSamples = convertToDecibels(fromAmplitudes: readBuffer, from: assetReader, groupSize: samplesToGroup)
            outputSamples += processedSamples

            // If we successfully processed samples, remove any processed samples
            // from the read buffer.
            if processedSamples.count > 0 {
                readBuffer.removeFirst(processedSamples.count * samplesToGroup * MemoryLayout<Int16>.size)
            }
        }

        return outputSamples
    }

    private func sampleCount(from assetReader: AVAssetReader) -> Int {
        let samplesPerChannel = Int(assetReader.asset.duration.value)

        // We will read in the samples from each channel, interleaved since
        // we only draw one waveform. This gives us an average of the channels
        // if it is, for example, a stereo audio file.
        return samplesPerChannel * channelCount(from: assetReader)
    }

    private func channelCount(from assetReader: AVAssetReader) -> Int {
        guard let output = assetReader.outputs.first as? AVAssetReaderTrackOutput,
            let formatDescriptions = output.track.formatDescriptions as? [CMFormatDescription] else { return 0 }

        var channelCount = 0

        for description in formatDescriptions {
            guard let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { continue }
            channelCount = Int(basicDescription.pointee.mChannelsPerFrame)
        }

        return channelCount
    }

    private func convertToDecibels(fromAmplitudes sampleBuffer: Data, from assetReader: AVAssetReader, groupSize: Int) -> [Float] {
        var downSampledData = [Float]()

        sampleBuffer.withUnsafeBytes { samples in
            let sampleLength = sampleBuffer.count / MemoryLayout<Int16>.size
            var decibelSamples = [Float](repeating: 0.0, count: sampleLength)

            // maximum amplitude storable in Int16 = 0 dB (loudest)
            var zeroDecibelEquivalent: Float = Float(Int16.max)

            var loudestClipValue: Float = 0.0
            var quietestClipValue = AudioWaveform.silenceThreshold
            let samplesToProcess = vDSP_Length(sampleLength)

            // convert 16bit int amplitudes to float representation
            vDSP_vflt16([Int16](samples.bindMemory(to: Int16.self)), 1, &decibelSamples, 1, samplesToProcess)

            // take the absolute amplitude value
            vDSP_vabs(decibelSamples, 1, &decibelSamples, 1, samplesToProcess)

            // convert to dB
            vDSP_vdbcon(decibelSamples, 1, &zeroDecibelEquivalent, &decibelSamples, 1, samplesToProcess, 1)

            // clip between loudest + quietest
            vDSP_vclip(decibelSamples, 1, &quietestClipValue, &loudestClipValue, &decibelSamples, 1, samplesToProcess)

            let sampleCount = sampleLength / groupSize
            downSampledData = downsample(samples: decibelSamples, toSampleCount: sampleCount)
        }

        return downSampledData
    }
}
