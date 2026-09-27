//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Accelerate
import AVFoundation
import Foundation

public protocol AudioWaveformManager {

    func cachedAudioWaveform(
        attachmentStream: AttachmentStream,
    ) -> Task<AudioWaveform, Error>

    func computeAndCacheAudioWaveform(
        audioPath: String,
        cacheWaveformToPath waveformPath: String,
    ) -> Task<AudioWaveform, Error>

    func computeAudioWaveform(
        audioFilePath: String,
    ) throws -> AudioWaveform

    func computeAudioWaveform(
        encryptedAudioFilePath: String,
        attachmentKey: AttachmentKey,
        plaintextDataLength: UInt32,
        mimeType: String,
    ) throws -> AudioWaveform
}

// MARK: -

class AudioWaveformManagerImpl: AudioWaveformManager {

    init() {}

    func cachedAudioWaveform(
        attachmentStream: AttachmentStream,
    ) -> Task<AudioWaveform, Error> {
        switch attachmentStream.contentType {
        case .file, .image, .video:
            return Task {
                throw OWSAssertionError("Unexpected contentType for audio waveform! \(attachmentStream.contentType)")
            }
        case .audio:
            break
        }

        // We failed to generate a waveform file when we downloaded the attachment,
        // so don't try again now.
        guard let audioWaveformRelativeFilePath = attachmentStream.cachedAudioWaveformRelativeFilePath else {
            return Task {
                throw OWSAssertionError("invalid audio file")
            }
        }

        return Task {
            let fileURL = AttachmentStream.absoluteAttachmentFileURL(
                relativeFilePath: audioWaveformRelativeFilePath,
            )
            // waveform is validated at creation time; no need to revalidate every read.
            let data = try Cryptography.decryptFileWithoutValidating(
                at: fileURL,
                metadata: DecryptionMetadata(key: AttachmentKey(
                    combinedKey: attachmentStream.attachment.encryptionKey,
                )),
            )
            return try AudioWaveform(archivedData: data)
        }
    }

    func computeAndCacheAudioWaveform(
        audioPath: String,
        cacheWaveformToPath: String,
    ) -> Task<AudioWaveform, Error> {
        return buildAudioWaveForm(
            source: .unencryptedFile(path: audioPath),
            cacheWaveformToPath: cacheWaveformToPath,
            identifier: .file(UUID()),
            highPriority: false,
        )
    }

    func computeAudioWaveform(
        audioFilePath: String,
    ) throws -> AudioWaveform {
        return try _buildAudioWaveForm(
            source: .unencryptedFile(path: audioFilePath),
            cacheWaveformToPath: nil,
        )
    }

    func computeAudioWaveform(
        encryptedAudioFilePath: String,
        attachmentKey: AttachmentKey,
        plaintextDataLength: UInt32,
        mimeType: String,
    ) throws -> AudioWaveform {
        return try _buildAudioWaveForm(
            source: .encryptedFile(
                path: encryptedAudioFilePath,
                attachmentKey: attachmentKey,
                plaintextDataLength: plaintextDataLength,
                mimeType: mimeType,
            ),
            cacheWaveformToPath: nil,
        )
    }

    private enum AVAssetSource {
        case unencryptedFile(path: String)
        case encryptedFile(
            path: String,
            attachmentKey: AttachmentKey,
            plaintextDataLength: UInt32,
            mimeType: String,
        )
    }

    private enum WaveformId: Hashable {
        case attachment(Attachment.IDType)
        case file(UUID)

        var cacheKey: Attachment.IDType? {
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
    private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
    private let highPriorityTaskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    private var cache = LRUCache<Attachment.IDType, Weak<AudioWaveform>>(maxSize: 64)

    private func buildAudioWaveForm(
        source: AVAssetSource,
        cacheWaveformToPath: String,
        identifier: WaveformId,
        highPriority: Bool,
    ) -> Task<AudioWaveform, Error> {
        return Task {
            if
                let cacheKey = identifier.cacheKey,
                let cachedValue = self.cache[cacheKey]?.value
            {
                return cachedValue
            }

            let taskQueue = highPriority ? self.highPriorityTaskQueue : self.taskQueue
            return try await taskQueue.runWithThrowingTask { [weak self] in
                guard let self else {
                    throw OWSAssertionError("Waveform manager deallocated!")
                }
                let waveform = try self._buildAudioWaveForm(
                    source: source,
                    cacheWaveformToPath: cacheWaveformToPath,
                )

                identifier.cacheKey.map { self.cache[$0] = Weak(value: waveform) }
                return waveform
            }
        }
    }

    /// - Parameter cacheWaveformToPath: if non-nil, writes a waveform file to
    /// this path.
    private func _buildAudioWaveForm(
        source: AVAssetSource,
        cacheWaveformToPath: String?,
    ) throws -> AudioWaveform {
        if let waveformPath = cacheWaveformToPath {
            do {
                let waveformData = try Data(contentsOf: URL(fileURLWithPath: waveformPath))
                // We have a cached waveform on disk, read it into memory.
                return try AudioWaveform(archivedData: waveformData)
            } catch POSIXError.ENOENT, CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
                // The file doesn't exist...
            } catch {
                owsFailDebug("Error: \(error)")
                // Remove the file from disk and create a new one.
                OWSFileSystem.deleteFileIfExists(waveformPath)
            }
        }

        let asset: AVAsset
        switch source {
        case .unencryptedFile(let path):
            asset = try assetFromUnencryptedAudioFile(atAudioPath: path)
        case let .encryptedFile(path, attachmentKey, plaintextDataLength, mimeType):
            asset = try assetFromEncryptedAudioFile(
                atPath: path,
                attachmentKey: attachmentKey,
                plaintextDataLength: plaintextDataLength,
                mimeType: mimeType,
            )
        }

        guard asset.isReadable else {
            throw OWSAssertionError("unexpectedly encountered unreadable audio file.")
        }

        guard CMTimeGetSeconds(asset.duration) <= Self.maximumDuration else {
            throw OWSAssertionError("audio too long for waveform: \(asset.duration)")
        }

        let waveform = try sampleWaveform(asset: asset)

        if let waveformPath = cacheWaveformToPath {
            do {
                let parentDirectoryPath = (waveformPath as NSString).deletingLastPathComponent
                if OWSFileSystem.ensureDirectoryExists(parentDirectoryPath) {
                    switch source {
                    case .unencryptedFile:
                        try waveform.write(toFile: waveformPath, atomically: true)
                    case .encryptedFile(_, let attachmentKey, _, _):
                        let waveformData = try waveform.archive()
                        let (encryptedWaveform, _) = try Cryptography.encrypt(waveformData, attachmentKey: attachmentKey)
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
        atAudioPath audioPath: String,
    ) throws -> AVAsset {
        let audioUrl = URL(fileURLWithPath: audioPath)

        var asset = AVURLAsset(url: audioUrl)

        if !asset.isReadable {
            if let extensionOverride = MimeTypeUtil.alternativeAudioFileExtension(fileExtension: audioUrl.pathExtension) {
                let symlinkPath = OWSFileSystem.temporaryFilePath(
                    fileExtension: extensionOverride,
                    isAvailableWhileDeviceLocked: true,
                )
                do {
                    try FileManager.default.createSymbolicLink(
                        atPath: symlinkPath,
                        withDestinationPath: audioPath,
                    )
                } catch {
                    throw OWSAssertionError("Failed to create voice memo symlink: \(error)")
                }
                asset = AVURLAsset(url: URL(fileURLWithPath: symlinkPath))
            }
        }

        return asset
    }

    private func assetFromEncryptedAudioFile(
        atPath filePath: String,
        attachmentKey: AttachmentKey,
        plaintextDataLength: UInt32,
        mimeType: String,
    ) throws -> AVAsset {
        let audioUrl = URL(fileURLWithPath: filePath)
        return try AVAsset.fromEncryptedFile(
            at: audioUrl,
            attachmentKey: attachmentKey,
            plaintextLength: plaintextDataLength,
            mimeType: mimeType,
        )
    }

    // MARK: - Sampling

    /// The maximum duration asset that we will display waveforms for.
    /// It's too intensive to sample a waveform for really long audio files.
    fileprivate static let maximumDuration: TimeInterval = 15 * .minute

    private func sampleWaveform(asset: AVAsset) throws -> AudioWaveform {
        try Task.checkCancellation()

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            throw OWSAssertionError("Unexpectedly failed to initialize asset reader")
        }

        // We just draw the waveform based on the first audio track.
        guard let audioTrack = assetReader.asset.tracks.first(where: { $0.mediaType == .audio }) else {
            throw OWSAssertionError("audio file has no tracks")
        }

        let trackOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ],
        )
        assetReader.add(trackOutput)

        let decibelSamples = try readDecibels(from: assetReader)

        try Task.checkCancellation()

        return AudioWaveform(decibelSamples: decibelSamples)
    }

    private func readDecibels(from assetReader: AVAssetReader) throws -> [Float] {
        let sampler = AudioWaveformSampler(
            inputCount: sampleCount(from: assetReader),
            outputCount: AudioWaveform.sampleCount,
        )

        assetReader.startReading()
        defer {
            // We may exit the loop below before we hit the end of the file.
            assetReader.cancelReading()
        }

        // Stop once we have all the samples we need. Only relevant for a file
        // whose container metadata understates its sample count.
        while
            assetReader.status == .reading,
            !sampler.isComplete
        {
            // Stop reading if the operation is cancelled.
            try Task.checkCancellation()

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
                dataPointerOut: &dataPointer,
            )
            guard result == kCMBlockBufferNoErr else {
                throw OWSAssertionError("track data unexpectedly inaccessible")
            }
            let bufferPointer = UnsafeBufferPointer(start: dataPointer, count: lengthAtOffset)
            bufferPointer.withMemoryRebound(to: Int16.self) { sampler.update($0) }
            CMSampleBufferInvalidate(nextSampleBuffer)
        }

        return sampler.finalize()
    }

    private func sampleCount(from assetReader: AVAssetReader) -> Int {
        let samplesPerChannel = Int(assetReader.asset.duration.value)
        let channelCount = channelCount(from: assetReader)

        // We will read in the samples from each channel, interleaved since
        // we only draw one waveform. This gives us an average of the channels
        // if it is, for example, a stereo audio file.
        //
        // samplesPerChannel comes from the container metadata and can be
        // misstated to be arbitrarily large, so guard the arithmetic here.
        let (sampleCount, overflow) = samplesPerChannel.multipliedReportingOverflow(
            by: channelCount,
        )
        guard !overflow else {
            return 0
        }
        return sampleCount
    }

    private func channelCount(from assetReader: AVAssetReader) -> Int {
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
