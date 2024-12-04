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

    private typealias AttachmentId = Attachment.IDType

    public init() {}

    public func audioWaveform(
        forAttachment attachment: AttachmentStream,
        highPriority: Bool
    ) -> Task<AudioWaveform, Error> {
        switch attachment.info.contentType {
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
            let encryptionKey = attachment.attachment.encryptionKey
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

    private func sampleWaveform(asset: AVAsset) throws -> AudioWaveform {
        try Task.checkCancellation()

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            owsFailDebug("Unexpectedly failed to initialize asset reader")
            throw AudioWaveformError.fileIOError
        }

        // We just draw the waveform based on the first audio track.
        guard let audioTrack = assetReader.asset.tracks.first(where: { $0.mediaType == .audio }) else {
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
        let sampler = AudioWaveformSampler(
            inputCount: sampleCount(from: assetReader),
            outputCount: AudioWaveform.sampleCount
        )

        assetReader.startReading()
        while assetReader.status == .reading {
            // Stop reading if the operation is cancelled.
            try Task.checkCancellation()

            guard let trackOutput = assetReader.outputs.first else {
                owsFailDebug("track output unexpectedly missing")
                throw AudioWaveformError.invalidAudioFile
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

    private func sampleCount(from assetReader: AVAssetReader) -> Int {
        let samplesPerChannel = Int(assetReader.asset.duration.value)

        // We will read in the samples from each channel, interleaved since
        // we only draw one waveform. This gives us an average of the channels
        // if it is, for example, a stereo audio file.
        return samplesPerChannel * channelCount(from: assetReader)
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
