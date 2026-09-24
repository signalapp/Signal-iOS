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

        if let waveformSamples = attachmentStream.audioDetails?.waveformSamples {
            return Task {
                AudioWaveform(waveformData: waveformSamples)
            }
        }

        // This attachment predates storing waveforms alongside the attachment
        // and hasn't been migrated yet, so read the waveform file instead.
        guard let waveformRelativeFilePath = attachmentStream.audioDetails?.waveformRelativeFilePath else {
            // We failed to generate a waveform when we downloaded the attachment,
            // so don't try again now.
            return Task {
                throw OWSAssertionError("invalid audio file")
            }
        }

        return Task {
            let fileURL = AttachmentStream.absoluteAttachmentFileURL(
                relativeFilePath: waveformRelativeFilePath,
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

    func computeAudioWaveform(
        audioFilePath: String,
    ) throws -> AudioWaveform {
        return try buildAudioWaveForm(source: .unencryptedFile(path: audioFilePath))
    }

    func computeAudioWaveform(
        encryptedAudioFilePath: String,
        attachmentKey: AttachmentKey,
        plaintextDataLength: UInt32,
        mimeType: String,
    ) throws -> AudioWaveform {
        return try buildAudioWaveForm(source: .encryptedFile(
            path: encryptedAudioFilePath,
            attachmentKey: attachmentKey,
            plaintextDataLength: plaintextDataLength,
            mimeType: mimeType,
        ))
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

    private func buildAudioWaveForm(source: AVAssetSource) throws -> AudioWaveform {
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

        return try sampleWaveform(asset: asset)
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

        return AudioWaveform(
            levels: decibelSamples.map { AudioWaveform.level(fromDecibels: $0) },
        )
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
