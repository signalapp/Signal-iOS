//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit
import UniformTypeIdentifiers

/// Represents ``PreviewableAttachment``s that are videos. This is roughly
/// equivalent to a "previewable video attachment".
///
/// This type (via `finalizeVideo`) can be used to produce a video that's
/// acceptable for sending via Signal.
public struct NormalizedVideo {
    let dataSource: DataSourcePath
    let dataUTI: String

    /// If true, this video must be transcoded when finalizing it. Otherwise,
    /// it's sent as-is unless it has been edited.
    let mustTranscode: Bool

    static func forDataSource(
        _ dataSource: DataSourcePath,
        dataUTI: String,
        mustTranscode: Bool,
    ) throws(SignalAttachmentError) -> Self {
        guard SignalAttachment.videoUTISet.contains(dataUTI) else {
            throw .invalidFileFormat
        }

        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            owsFailDebug("Empty video")
            throw .invalidData
        }

        return NormalizedVideo(
            dataSource: dataSource,
            dataUTI: dataUTI,
            mustTranscode: mustTranscode,
        )
    }

    /// The unedited video.
    var sourceAsset: AVAsset {
        return AVURLAsset(url: dataSource.fileUrl)
    }

    // MARK: - Finalizing

    struct FinalizedVideo {
        let dataSource: DataSourcePath
        let dataUTI: String
    }

    /// - Parameter editedAsset
    /// This video with edits applied, or `nil` if it hasn't been edited.
    @concurrent
    func finalizeVideo(
        editedAsset: AVAsset?,
        imageQuality: ImageQuality,
        attachmentLimits: OutgoingAttachmentLimits,
        progress: Progress?,
    ) async throws -> FinalizedVideo {
        Logger.info("finalizing (mustTranscode: \(mustTranscode), isEdited: \(editedAsset != nil))")
        let outputUrl: URL
        if mustTranscode {
            outputUrl = try await transcode(
                asset: editedAsset ?? sourceAsset,
                imageQuality: imageQuality,
                attachmentLimits: attachmentLimits,
                progress: progress,
            )
        } else if let editedAsset {
            outputUrl = try await exportPassthrough(asset: editedAsset)
        } else {
            return FinalizedVideo(dataSource: dataSource, dataUTI: dataUTI)
        }

        let mp4DataSource = DataSourcePath(fileUrl: outputUrl, ownership: .owned)
        if
            let sourceFilename = dataSource.sourceFilename,
            let mp4Filename = ((sourceFilename as NSString).deletingPathExtension as NSString)
                .appendingPathExtension("mp4")
        {
            mp4DataSource.sourceFilename = mp4Filename
        }
        return FinalizedVideo(
            dataSource: mp4DataSource,
            dataUTI: UTType.mpeg4Movie.identifier,
        )
    }

    private func transcode(
        asset: AVAsset,
        imageQuality: ImageQuality,
        attachmentLimits: OutgoingAttachmentLimits,
        progress: Progress?,
    ) async throws -> URL {
        let startTime = MonotonicDate()
        let outputUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: "mp4",
            isAvailableWhileDeviceLocked: false,
        )

        do {
            let standardSettings = switch attachmentLimits.standardQualityLevel {
            case .one:
                VideoTranscoding.Settings.level1
            case .two, .three:
                VideoTranscoding.Settings.level2
            }
            let settings = switch imageQuality {
            case .standard:
                standardSettings
            case .high:
                VideoTranscoding.Settings.high + standardSettings
            }
            try await VideoTranscoding.transcodeMp4(
                asset: asset,
                settings: settings,
                outputUrl: outputUrl,
                progress: progress,
            )
        } catch let e as CancellationError {
            throw e
        } catch let e as VideoTranscoding.VideoTooLongForSettingsError {
            throw SignalAttachmentError.videoTooLong(maxDuration: e.maxAllowedDuration)
        } catch {
            throw OWSAssertionError("export failed: \(error)")
        }

        let endTime = MonotonicDate()
        let formattedDuration = OWSOperation.formattedNs((endTime - startTime).nanoseconds)
        Logger.info("transcoded video in \(formattedDuration)s")
        return outputUrl
    }

    /// Writes `asset` to an mp4 without re-encoding it.
    private func exportPassthrough(asset: AVAsset) async throws -> URL {
        let startTime = MonotonicDate()
        let outputUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: "mp4",
            isAvailableWhileDeviceLocked: false,
        )

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw OWSAssertionError("couldn't create export session")
        }

        // This will ensure that the MP4 moov atom (movie atom)
        // is located at the beginning of the file. That may help
        // recipients validate incoming videos.
        session.shouldOptimizeForNetworkUse = true

        try await session.exportAsync(to: outputUrl, as: .mp4)

        let endTime = MonotonicDate()
        let formattedDuration = OWSOperation.formattedNs((endTime - startTime).nanoseconds)
        Logger.info("exported video in \(formattedDuration)s")

        switch session.status {
        case .completed:
            return outputUrl
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? OWSAssertionError("status \(session.status)")
        }
    }
}
