//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Dispatch
import SignalServiceKit

enum VideoTranscoding {
    struct Settings {
        var maxAllowedDuration: TimeInterval
        var maxResolution: CGFloat
        var videoMegabitsPerSecond: Double
        var audioKilobitsPerSecond: Double

        static let level1: [Settings] = [
            Settings(
                maxAllowedDuration: 15 * .minute,
                maxResolution: 640 /* 480p */,
                videoMegabitsPerSecond: 1.0,
                audioKilobitsPerSecond: 128.0,
            ),
        ]

        static let level2: [Settings] = [
            Settings(
                maxAllowedDuration: 10 * .minute,
                maxResolution: 1280 /* 720p */,
                videoMegabitsPerSecond: 2.0,
                audioKilobitsPerSecond: 128.0,
            ),
            Settings(
                maxAllowedDuration: 15 * .minute,
                maxResolution: 1280 /* 720p */,
                videoMegabitsPerSecond: 1.5,
                audioKilobitsPerSecond: 128.0,
            ),
        ]

        static let high: [Settings] = [
            Settings(
                maxAllowedDuration: 6 * .minute,
                maxResolution: 1280 /* 720p */,
                videoMegabitsPerSecond: 4.0,
                audioKilobitsPerSecond: 128.0,
            ),
        ]
    }

    // MARK: - Errors

    struct IndeterminateReaderError: Error {
        let status: AVAssetReader.Status
    }

    struct IndeterminateWriterError: Error {
        let status: AVAssetWriter.Status
    }

    struct VideoTooLongForSettingsError: Error {
        /// The longest duration allowed by any of the settings options.
        let maxAllowedDuration: TimeInterval
    }

    // MARK: -

    private static let logger = PrefixedLogger(prefix: "[VideoTransc]")

    /// Transcodes the given `asset` to `outputUrl` with the given settings.
    ///
    /// - Parameter settings
    /// Settings options. The first valid option is used.
    @concurrent
    static func transcodeMp4(
        asset: AVAsset,
        settings settingChoices: [Settings],
        outputUrl: URL,
        progress: Progress?,
    ) async throws {
        await logSource(asset: asset)

        let duration = try await asset.load(.duration)
        guard let settings = settingChoices.first(where: { $0.maxAllowedDuration >= duration.seconds }) else {
            throw VideoTooLongForSettingsError(
                maxAllowedDuration: settingChoices.map { $0.maxAllowedDuration }.max() ?? 0,
            )
        }

        // Divide up the progress reporting for "time reading the input" and "time finalizing the output".
        // If we only did the first, we could end up showing the user a static 100% completion for a while.
        let readProgress = Progress(totalUnitCount: Int64(duration.seconds * 1000.0))
        let finishProgress = Progress(totalUnitCount: 1)
        progress?.totalUnitCount = 10
        progress?.addChild(readProgress, withPendingUnitCount: 8)
        progress?.addChild(finishProgress, withPendingUnitCount: 2)

        guard !FileManager.default.fileExists(atPath: outputUrl.path) else {
            throw OWSGenericError("output file already exists")
        }

        // Write the output and any intermediate files to a dedicated temporary
        // directory, then move the output into place once it's complete.
        let temporaryOutputUrl = OWSFileSystem.temporaryFileUrl(
            fileName: "transcode",
            fileExtension: "mp4",
            isAvailableWhileDeviceLocked: false,
        )
        let temporaryDirectory = temporaryOutputUrl.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(url: temporaryOutputUrl, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.directoryForTemporaryFiles = temporaryDirectory
        writer.overallDurationHint = duration

        writer.metadata = AVMetadataItem.metadataItems(
            from: try await asset.load(.metadata),
            filteredBy: .forSharing(),
        )
        let metadataKeys = writer.metadata.map { $0.identifier?.rawValue ?? "?" }
        logger.info("copying metadata: \(metadataKeys)")

        guard
            let videoTrack = try await TrackPipe(
                trackType: .video,
                settings: settings,
                asset: asset,
                reader: reader,
                writer: writer,
            )
        else {
            throw OWSGenericError("Missing video track!")
        }

        let audioTrack = try await TrackPipe(
            trackType: .audio,
            settings: settings,
            asset: asset,
            reader: reader,
            writer: writer,
        )

        // One last check for cancellation before we start processing samples.
        try Task.checkCancellation()

        try await _transcodeSamples(
            reader: reader,
            writer: writer,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            readProgress: readProgress,
            finishProgress: finishProgress,
        )

        try FileManager.default.moveItem(at: temporaryOutputUrl, to: outputUrl)
    }

    // Unfortunately, the AVAsset sample-buffer-based APIs don't support
    // Swift async until iOS 26. We make do with the GCD-based APIs instead,
    // which involves some nonisolated(unsafe) that matches the behavior of
    // Apple's older (Objective-C) sample code. This function encapsulates that.
    @available(iOS, deprecated: 26, message: "should be replaced with an async implementation once available")
    private static func _transcodeSamples(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoTrack: TrackPipe,
        audioTrack: TrackPipe?,
        readProgress: Progress,
        finishProgress: Progress,
    ) async throws {
        let serialQueue = DispatchQueue(label: "AttachmentTranscoding", qos: .userInitiated)

        // Make an explicit DispatchWorkItem for cancellation so that we can chain
        // the async continuation to it below.
        // This is only mutable for the self-reference; it will not be modified
        // again after the initial set.
        nonisolated(unsafe) var cancelWriterAndReader: DispatchWorkItem!
        cancelWriterAndReader = DispatchWorkItem {
            // cancelWriting and cancelReading are documented as
            // "don't call this concurrently with doing any writing/reading".
            // So we have to be sure we're synchronizing with any reader/writer tasks.
            assertOnQueue(serialQueue)

            // Only run cancellation once. Also indicates that we have, in fact,
            // cancelled.
            cancelWriterAndReader.cancel()

            writer.cancelWriting()
            reader.cancelReading()
        }

        // Once finalizing has started, let it complete rather than cancel the
        // writer mid-finish.
        let isFinalizing = AtomicBool(false, lock: UnfairLock())

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // We won't access these off the queue after this (except where captured above).
                nonisolated(unsafe) let transferReader = reader
                nonisolated(unsafe) let transferWriter = writer
                // Actually set everything up on the serialQueue, which is marked as userInitiated,
                // so that the blocking calls in e.g. startReading() aren't being done on an arbitrary Task.
                serialQueue.async {
                    _transcodeSamples(
                        reader: transferReader,
                        writer: transferWriter,
                        videoTrack: videoTrack,
                        audioTrack: audioTrack,
                        readProgress: readProgress,
                        finishProgress: finishProgress,
                        serialQueue: serialQueue,
                        cancelWriterAndReader: cancelWriterAndReader,
                        isFinalizing: isFinalizing,
                        continuation: continuation,
                    )
                }
            }
        } onCancel: {
            serialQueue.async {
                // Don't execute the work item at all if finalizing, since doing
                // so would trigger its notify and resume the continuation.
                if isFinalizing.get() {
                    return
                }

                cancelWriterAndReader.perform()
            }
        }
    }

    @available(iOS, deprecated: 26, message: "should be replaced with an async implementation once available")
    private static func _transcodeSamples(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoTrack: TrackPipe,
        audioTrack: TrackPipe?,
        readProgress: Progress,
        finishProgress: Progress,
        serialQueue: DispatchQueue,
        cancelWriterAndReader: DispatchWorkItem,
        isFinalizing: AtomicBool,
        continuation: CheckedContinuation<Void, Error>,
    ) {
        assertOnQueue(serialQueue)

        // If we've already cancelled the writer and reader, then attempting to
        // start them will raise an exception.
        if cancelWriterAndReader.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }

        if !reader.startReading() {
            logger.warn("startReading failed; \(describeState(reader: reader, writer: writer))")
            continuation.resume(throwing: reader.error ?? IndeterminateReaderError(status: reader.status))
            return
        }
        if !writer.startWriting() {
            logger.warn("startWriting failed; \(describeState(reader: reader, writer: writer))")
            continuation.resume(throwing: writer.error ?? IndeterminateWriterError(status: writer.status))
            return
        }
        writer.startSession(atSourceTime: .zero)

        // Capture a closure for checking the final state of the reader and writer.
        // The `error` and `status` properties are specifically marked as thread-safe.
        let checkFinalErrors = { () throws in
            if reader.error != nil || writer.error != nil {
                logger.warn("ended with errors; \(describeState(reader: reader, writer: writer))")
            }

            // Prefer errors in the reader over errors in the writer...
            if let error = reader.error {
                throw error
            }
            if let error = writer.error {
                throw error
            }

            // ...but if there are no explicit errors, the writer's status is more interesting.
            let writerStatus = writer.status
            switch writerStatus {
            case .completed: break
            case .cancelled: throw CancellationError()
            case .writing, .failed, .unknown: fallthrough
            @unknown default: throw IndeterminateWriterError(status: writerStatus)
            }

            if reader.status != .completed {
                throw IndeterminateReaderError(status: reader.status)
            }
        }

        // Ensure we never forget to fulfill the continuation by wrapping it in
        // a work item, which we'll then both attach to the cancellation work item
        // as well as invoking it directly on successful completion.
        // A DispatchWorkItem with a Sendable closure should be Sendable,
        // the type system just can't express that.
        // (And the var is only mutable for the self-reference; it will not be modified
        // again after the initial set.)
        nonisolated(unsafe) var fulfillContinuation: DispatchWorkItem!
        fulfillContinuation = DispatchWorkItem { @Sendable in
            // Check that we're on the serial queue to make sure
            // we're not going to fulfill the continuation twice concurrently.
            assertOnQueue(serialQueue)
            // Prevent multiple execution.
            fulfillContinuation.cancel()
            do {
                try checkFinalErrors()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        // If we get cancelled, make sure we fulfill the continuation.
        // Note that this will be scheduled immediately if the cancellation has already happened.
        cancelWriterAndReader.notify(queue: serialQueue, execute: fulfillContinuation)

        let finishWriting = {
            assertOnQueue(serialQueue)
            isFinalizing.set(true)
            writer.finishWriting {
                finishProgress.completedUnitCount = finishProgress.totalUnitCount
                serialQueue.async(execute: fulfillContinuation)
            }
        }

        var videoDone = false
        var audioDone = audioTrack == nil
        videoTrack.copySamples(serialQueue: serialQueue, progress: readProgress) { result in
            switch result {
            case .finished:
                videoDone = true
                if audioDone {
                    finishWriting()
                }
            case .halted(let reason):
                let state = describeState(reader: reader, writer: writer)
                logger.warn("video halted: \(reason); \(state)")
                cancelWriterAndReader.perform()
            }
        }
        if let audioTrack {
            audioTrack.copySamples(serialQueue: serialQueue, progress: nil) { result in
                switch result {
                case .finished:
                    audioDone = true
                    if videoDone {
                        finishWriting()
                    }
                case .halted(let reason):
                    let state = describeState(reader: reader, writer: writer)
                    logger.warn("audio halted: \(reason); \(state)")
                    cancelWriterAndReader.perform()
                }
            }
        }
    }

    // MARK: - Logging

    private static func describeState(reader: AVAssetReader, writer: AVAssetWriter) -> String {
        let readerError = reader.error.map { "\($0)" } ?? "nil"
        let writerError = writer.error.map { "\($0)" } ?? "nil"
        return "reader: (status: \(reader.status.rawValue), error: \(readerError)), "
            + "writer: (status: \(writer.status.rawValue), error: \(writerError))"
    }

    private static func logSource(asset: AVAsset) async {
        do {
            let description = try await describe(asset: asset)
            logger.info("source: \(description)")
        } catch {
            logger.warn("couldn't describe source: \(error)")
        }
    }

    private static func describe(asset: AVAsset) async throws -> String {
        let duration: CMTime
        let tracks: [AVAssetTrack]
        (duration, tracks) = try await asset.load(.duration, .tracks)
        var parts = [
            "type: \(type(of: asset))",
            "duration: \(duration.seconds)s",
        ]
        for track in tracks {
            let trackDescription = try await describe(track: track)
            parts.append("[\(trackDescription)]")
        }
        return parts.joined(separator: ", ")
    }

    private static func describe(track: AVAssetTrack) async throws -> String {
        let mediaType = track.mediaType
        let formats: [CMFormatDescription]
        let isEnabled: Bool
        (formats, isEnabled) = try await track.load(.formatDescriptions, .isEnabled)
        var parts = [
            "id: \(track.trackID)",
            "type: \(mediaType.rawValue)",
            "enabled: \(isEnabled)",
        ]

        switch mediaType {
        case .video:
            let isDecodable: Bool
            let timeScale: CMTimeScale
            let size: CGSize
            let frameRate: Float
            let transform: CGAffineTransform
            let dataRate: Float
            let characteristics: [AVMediaCharacteristic]
            (
                isDecodable,
                timeScale,
                size,
                frameRate,
                transform,
                dataRate,
                characteristics,
            ) = try await track.load(
                .isDecodable,
                .naturalTimeScale,
                .naturalSize,
                .nominalFrameRate,
                .preferredTransform,
                .estimatedDataRate,
                .mediaCharacteristics,
            )
            parts += [
                "decodable: \(isDecodable)",
                "timeScale: \(timeScale)",
                "size: \(size)",
                "fps: \(frameRate)",
                "transform: \(transform)",
                "dataRate: \(dataRate)",
                "characteristics: \(characteristics.map { $0.rawValue })",
            ]
        case .audio:
            let isDecodable: Bool
            let dataRate: Float
            (isDecodable, dataRate) = try await track.load(.isDecodable, .estimatedDataRate)
            let fallbacks = try await track.loadAssociatedTracks(ofType: .audioFallback)
            parts += [
                "decodable: \(isDecodable)",
                "dataRate: \(dataRate)",
                "fallback: \(fallbacks.map { $0.trackID })",
            ]
        default:
            break
        }

        parts += formats.map { describe(format: $0) }
        return parts.joined(separator: ", ")
    }

    private static func describe(format: CMFormatDescription) -> String {
        var parts = ["codec: \(fourCC(CMFormatDescriptionGetMediaSubType(format)))"]
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            parts += [
                "sampleRate: \(asbd.mSampleRate)",
                "channels: \(asbd.mChannelsPerFrame)",
            ]
        }
        if let layout = CMAudioFormatDescriptionGetChannelLayout(format, sizeOut: nil)?.pointee {
            parts.append("layoutTag: 0x\(String(layout.mChannelLayoutTag, radix: 16))")
        }

        let extensionValueKeys: [CFString] = [
            kCMFormatDescriptionExtension_BitsPerComponent,
            kCMFormatDescriptionExtension_ColorPrimaries,
            kCMFormatDescriptionExtension_TransferFunction,
            kCMFormatDescriptionExtension_YCbCrMatrix,
        ]
        for key in extensionValueKeys {
            if let value = CMFormatDescriptionGetExtension(format, extensionKey: key) {
                parts.append("\(key): \(value)")
            }
        }

        return "[\(parts.joined(separator: ", "))]"
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    // MARK: -

    private struct TrackPipe {
        private let reader: AVAssetReader
        private let writer: AVAssetWriter
        private let trackReaderOutput: AVAssetReaderTrackOutput
        private let trackWriterInput: AVAssetWriterInput

        enum TrackType {
            case audio
            case video

            func mediaType() -> AVMediaType {
                switch self {
                case .audio:
                    .audio
                case .video:
                    .video
                }
            }
        }

        init?(
            trackType: TrackType,
            settings: Settings,
            asset: AVAsset,
            reader: AVAssetReader,
            writer: AVAssetWriter,
        ) async throws {
            let tracks = try await asset.loadTracks(withMediaType: trackType.mediaType())
            guard let track = try await Self.bestTrack(tracks) else {
                return nil
            }
            VideoTranscoding.logger.info("using \(trackType) track \(track.trackID)")

            let readerSettings: [String: Any]?
            switch trackType {
            case .video:
                readerSettings = [
                    String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                ]
            case .audio:
                readerSettings = [AVFormatIDKey: kAudioFormatLinearPCM]
            }
            let trackReaderOutput = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: readerSettings,
            )
            trackReaderOutput.alwaysCopiesSampleData = false
            reader.add(trackReaderOutput)

            let trackWriterInput: AVAssetWriterInput
            switch trackType {
            case .video:
                let (size, transform, timeScale) = try await track.load(
                    .naturalSize,
                    .preferredTransform,
                    .naturalTimeScale,
                )

                guard
                    size.width.isFinite, size.width > 0,
                    size.height.isFinite, size.height > 0
                else {
                    throw OWSGenericError("invalid video track size \(size)")
                }
                let maxDim = max(size.width, size.height)
                let outputSize: CGSize
                if maxDim <= settings.maxResolution {
                    outputSize = size
                } else {
                    // TODO: WebRTC tries to make this a low-weight fraction for cleaner scaling.
                    let factor = settings.maxResolution / maxDim
                    outputSize = size * factor
                }

                // Round to the nearest even dimension ourselves; otherwise
                // AVFoundation rounds down on our behalf and may skew the
                // aspect ratio.
                func roundedToEven(_ dimension: CGFloat) -> Int {
                    max(2, Int((dimension / 2).rounded()) * 2)
                }

                let outputWidth = roundedToEven(outputSize.width)
                let outputHeight = roundedToEven(outputSize.height)
                VideoTranscoding.logger.info(
                    "video output: \(outputWidth)x\(outputHeight), "
                        + "\(settings.videoMegabitsPerSecond) Mbps, timeScale: \(timeScale)",
                )

                trackWriterInput = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: outputWidth,
                        AVVideoHeightKey: outputHeight,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: settings.videoMegabitsPerSecond * 1_000_000.0,
                            // These settings are subject to tweaking
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                        ],
                        // Force rec.709 (we might want to enable HDR at higher bitrates, but we'll set that option later)
                        AVVideoColorPropertiesKey: [
                            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                        ],
                        // AVVideoCompressionPropertiesKey can let us specify lower level properties
                    ],
                    sourceFormatHint: nil,
                )
                trackWriterInput.transform = transform
                trackWriterInput.mediaTimeScale = timeScale
            case .audio:
                trackWriterInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC, // TODO: do we want high efficiency AAC?
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                        // We could choose 48 kHz instead. 44.1 kHz is going to be smaller tho
                        AVSampleRateKey: 44_100,
                        AVNumberOfChannelsKey: 2,
                        AVEncoderBitRateKey: settings.audioKilobitsPerSecond * 1_000.0,
                    ],
                    sourceFormatHint: nil,
                )
            }
            trackWriterInput.expectsMediaDataInRealTime = false
            writer.add(trackWriterInput)

            self.reader = reader
            self.writer = writer
            self.trackReaderOutput = trackReaderOutput
            self.trackWriterInput = trackWriterInput
        }

        /// Choose the track with the most sample data.
        private static func bestTrack(_ tracks: [AVAssetTrack]) async throws -> AVAssetTrack? {
            var winner: AVAssetTrack? = nil
            var winnerSize: Int64 = 0
            for track in tracks {
                let (isEnabled, isDecodable) = try await track.load(.isEnabled, .isDecodable)
                guard isEnabled, isDecodable else {
                    continue
                }
                // We could optimistically fold this into the load above, but for a track that is NOT
                // decodable this might produce an error. Better to check that first.
                let size = try await track.load(.totalSampleDataLength)
                // Composition tracks may report no sample data.
                if winner == nil || size > winnerSize {
                    winnerSize = size
                    winner = track
                }
            }
            return winner
        }

        enum CopyResult {
            case finished
            case halted(reason: String)
        }

        @available(iOS, deprecated: 26, message: "should be replaced with an async implementation once available")
        func copySamples(
            serialQueue: DispatchQueue,
            progress: Progress?,
            completion: @escaping (CopyResult) -> Void,
        ) {
            // This captures the reader and writer, but only to read the `status` properties of each,
            // which are documented as thread-safe.
            nonisolated(unsafe) let canProceed = { [reader, writer] () -> Bool in
                let readerStatus = reader.status
                switch readerStatus {
                case .reading, .completed: break
                case .cancelled, .failed, .unknown: return false
                @unknown default:
                    VideoTranscoding.logger.warn(
                        "unrecognized AVAssetReaderStatus \(readerStatus); halting transcoding",
                    )
                    return false
                }

                let writerStatus = writer.status
                switch writerStatus {
                case .writing: break
                case .completed, .cancelled, .failed, .unknown: return false
                @unknown default:
                    VideoTranscoding.logger.warn(
                        "unrecognized AVAssetWriterStatus \(writerStatus); halting transcoding",
                    )
                    return false
                }

                return true
            }

            assertOnQueue(serialQueue)
            var completion: Optional = completion
            func complete(_ result: CopyResult) {
                assertOnQueue(serialQueue)
                completion?(result)
                // Protect against multiple calls.
                completion = nil
            }

            // These are not accessed on the original thread after processing starts.
            nonisolated(unsafe) let input = self.trackWriterInput
            nonisolated(unsafe) let output = self.trackReaderOutput
            var lastProgressUpdate: TimeInterval = 0
            var appended = 0

            func halt(_ reason: String) {
                complete(.halted(reason: "\(reason) after \(appended) samples"))
            }

            input.requestMediaDataWhenReady(on: serialQueue) {
                while input.isReadyForMoreMediaData {
                    if !canProceed() {
                        halt("can't proceed")
                        return
                    }

                    guard let buf = output.copyNextSampleBuffer() else {
                        if canProceed() {
                            input.markAsFinished()
                            complete(.finished)
                        } else {
                            halt("no more samples")
                        }
                        return
                    }

                    if !input.append(buf) {
                        // This isn't a transient failure, so we have to conclude here.
                        // We'll check the issue later.
                        halt("append failed at \(buf.presentationTimeStamp.seconds)s")
                        return
                    }
                    appended += 1

                    if let progress {
                        let time = buf.presentationTimeStamp.seconds
                        // Only update every second of media time.
                        if time - lastProgressUpdate > 1 {
                            lastProgressUpdate = time
                            // Units are milliseconds. Don't go backwards, also don't exceed
                            // our original estimation.
                            progress.completedUnitCount = Int64(time * 1000)
                                .clamped(to: progress.completedUnitCount...progress.totalUnitCount)
                        }
                    }
                }
            }
        }
    }
}

// MARK: -

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
