//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension TSAttachmentMigration {

    /// Migration for StoryMessage-owned TSAttachments.
    /// After migrating they are v2 attachments in the StoryMessageAttachmentReference table.
    ///
    /// The migration works in two passes which must happen in separate write transactions but
    /// must be run back to back. (Why? Filesystem changes are not part of the db transaction,
    /// so we need to first "reserve" the final file location in the db and then write the file. If the latter
    /// step fails we will just rewrite to the same file location next time we retry.)
    ///
    /// Phase 1: Read the StoryMessage table, for each story message create
    /// a TSAttachmentMigration row with the "reserved" (random) final file location.
    ///
    /// Phase 2: for each reserved file location, do attachment validation and create the v2 attachments.
    ///
    /// This migration is run up front as a blocking GRDB migration, because most people have very
    /// few story messages so its not worth the complexity to run this incrementally.
    enum StoryMessageMigration {

        /// Phase 1
        static func prepareStoryMessageMigration(tx: GRDBWriteTransaction) throws {
            let storyMessageCursor = try Row.fetchCursor(
                tx.database,
                sql: "SELECT id, attachment FROM model_StoryMessage"
            )
            // The `attachment` column is a SerializedStoryMessageAttachment encoded as a JSON string.
            let decoder = JSONDecoder()
            while let storyMessageRow = try storyMessageCursor.next() {
                guard
                    let storyMessageRowId = storyMessageRow["id"] as? Int64,
                    let storyAttachmentString = storyMessageRow["attachment"] as? String,
                    let storyMessageAttachmentData = storyAttachmentString.data(using: .utf8)
                else {
                    throw OWSAssertionError("Unexpected row format")
                }
                let storyAttachment = try decoder.decode(
                    TSAttachmentMigration.SerializedStoryMessageAttachment.self,
                    from: storyMessageAttachmentData
                )
                guard let tsAttachmentUniqueId = storyAttachment.tsAttachmentUniqueId else { continue }

                var reservedFileIds = TSAttachmentMigration.V1AttachmentReservedFileIds(
                    tsAttachmentUniqueId: tsAttachmentUniqueId,
                    interactionRowId: nil,
                    storyMessageRowId: storyMessageRowId,
                    reservedV2AttachmentPrimaryFileId: UUID(),
                    reservedV2AttachmentAudioWaveformFileId: UUID(),
                    reservedV2AttachmentVideoStillFrameFileId: UUID()
                )
                try reservedFileIds.insert(tx.database)
            }
        }

        /// Phase 2
        static func completeStoryMessageMigration(tx: GRDBWriteTransaction) throws {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            let reservedFileIdsCursor = try TSAttachmentMigration.V1AttachmentReservedFileIds
                .filter(Column("storyMessageRowId") != nil)
                .fetchCursor(tx.database)
            var deletedAttachments = [TSAttachmentMigration.V1Attachment]()
            while let reservedFileIds = try reservedFileIdsCursor.next() {
                guard let storyMessageRowId = reservedFileIds.storyMessageRowId else {
                    continue
                }
                let storyAttachmentString = try String.fetchOne(
                    tx.database,
                    sql: "SELECT attachment FROM model_StoryMessage WHERE id = ?;",
                    arguments: [storyMessageRowId]
                )
                guard
                    let storyAttachmentString,
                    let storyMessageAttachmentData = storyAttachmentString.data(using: .utf8)
                else {
                    reservedFileIds.cleanUpFiles()
                    continue
                }
                // The `attachment` column is a SerializedStoryMessageAttachment encoded as a JSON string.
                let storyAttachment = try decoder.decode(
                    TSAttachmentMigration.SerializedStoryMessageAttachment.self,
                    from: storyMessageAttachmentData
                )
                guard let tsAttachmentUniqueId = storyAttachment.tsAttachmentUniqueId else {
                    reservedFileIds.cleanUpFiles()
                    continue
                }
                try Self.migrateStoryMessageAttachment(
                    reservedFileIds: reservedFileIds,
                    storyAttachment: storyAttachment,
                    storyMessageRowId: storyMessageRowId,
                    tsAttachmentUniqueId: tsAttachmentUniqueId,
                    tx: tx
                )
                // Update the story message.
                let updatedStoryAttachment: TSAttachmentMigration.SerializedStoryMessageAttachment = {
                    switch storyAttachment {
                    case .file, .fileV2, .foreignReferenceAttachment:
                        return .foreignReferenceAttachment
                    case .text(var textAttachment):
                        let preview = textAttachment.preview
                        preview?.imageAttachmentId = nil
                        preview?.usesV2AttachmentReferenceValue = NSNumber(value: true)
                        textAttachment.preview = preview
                        return .text(attachment: textAttachment)
                    }
                }()
                let updatedStoryAttachmentRaw = try encoder.encode(updatedStoryAttachment)
                try tx.database.execute(
                    sql: """
                        UPDATE model_StoryMessage
                        SET attachment = ?
                        WHERE id = ?;
                        """,
                    arguments: [updatedStoryAttachmentRaw, storyMessageRowId]
                )

                // Delete the attachment.
                let deletedAttachment = try TSAttachmentMigration.V1Attachment.fetchOne(
                    tx.database,
                    sql: "DELETE FROM model_TSAttachment WHERE uniqueId = ? RETURNING *",
                    arguments: [tsAttachmentUniqueId]
                )
                deletedAttachment.map { deletedAttachments.append($0) }
            }

            // Delete our reserved rows.
            try TSAttachmentMigration.V1AttachmentReservedFileIds
                .filter(Column("storyMessageRowId") != nil)
                .deleteAll(tx.database)

            tx.addAsyncCompletion(queue: .global()) {
                // Delete the files asynchronously after committing the tx. We can't do it
                // inside the tx because if the tx is rolled back we DON'T want the files gone.
                // This does mean we might fail to delete the files; we will delete the whole
                // TSAttachment folder after migrating everything anyway so its not a huge deal.
                deletedAttachments.forEach { try? $0.deleteFiles() }
            }
        }

        /// Migrates a single story message's attachment.
        private static func migrateStoryMessageAttachment(
            reservedFileIds: TSAttachmentMigration.V1AttachmentReservedFileIds,
            storyAttachment: TSAttachmentMigration.SerializedStoryMessageAttachment,
            storyMessageRowId: Int64,
            tsAttachmentUniqueId: String,
            tx: GRDBWriteTransaction
        ) throws {
            let oldAttachment = try TSAttachmentMigration.V1Attachment
                .filter(Column("uniqueId") == tsAttachmentUniqueId)
                .fetchOne(tx.database)
            guard let oldAttachment else {
                reservedFileIds.cleanUpFiles()
                return
            }

            let renderingFlag = oldAttachment.attachmentType.asRenderingFlag

            let pendingAttachment: TSAttachmentMigration.PendingV2AttachmentFile?
            if let oldFilePath = oldAttachment.localFilePath {
                do {
                    pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.validateContents(
                        unencryptedFileUrl: URL(fileURLWithPath: oldFilePath),
                        reservedFileIds: .init(
                            primaryFile: reservedFileIds.reservedV2AttachmentPrimaryFileId,
                            audioWaveform: reservedFileIds.reservedV2AttachmentAudioWaveformFileId,
                            videoStillFrame: reservedFileIds.reservedV2AttachmentVideoStillFrameFileId
                        ),
                        encryptionKey: oldAttachment.encryptionKey,
                        mimeType: oldAttachment.contentType,
                        renderingFlag: renderingFlag,
                        sourceFilename: oldAttachment.sourceFilename
                    )
                } catch {
                    Logger.error("Failed to read story attachment file \((error as NSError).domain) \((error as NSError).code)")
                    // Clean up files just in case.
                    reservedFileIds.cleanUpFiles()
                    pendingAttachment = nil
                }
            } else {
                // A pointer; no validation needed.
                pendingAttachment = nil
                // Clean up files just in case.
                reservedFileIds.cleanUpFiles()
            }

            let v2AttachmentId: Int64
            if
                let pendingAttachment,
                let existingV2Attachment = try TSAttachmentMigration.V2Attachment
                    .filter(Column("sha256ContentHash") == pendingAttachment.sha256ContentHash)
                    .fetchOne(tx.database)
            {
                // If we already have a v2 attachment with the same plaintext hash,
                // create new references to it and drop the pending attachment.
                v2AttachmentId = existingV2Attachment.id!
                // Delete the reserved files being used by the pending attachment.
                reservedFileIds.cleanUpFiles()
            } else {
                var v2Attachment: TSAttachmentMigration.V2Attachment
                if let pendingAttachment {
                    v2Attachment = TSAttachmentMigration.V2Attachment(
                        blurHash: pendingAttachment.blurHash,
                        sha256ContentHash: pendingAttachment.sha256ContentHash,
                        encryptedByteCount: pendingAttachment.encryptedByteCount,
                        unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                        mimeType: pendingAttachment.mimeType,
                        encryptionKey: pendingAttachment.encryptionKey,
                        digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                        contentType: UInt32(pendingAttachment.validatedContentType.rawValue),
                        transitCdnNumber: oldAttachment.cdnNumber,
                        transitCdnKey: oldAttachment.cdnKey,
                        transitUploadTimestamp: oldAttachment.uploadTimestamp,
                        transitEncryptionKey: oldAttachment.encryptionKey,
                        transitUnencryptedByteCount: pendingAttachment.unencryptedByteCount,
                        transitDigestSHA256Ciphertext: oldAttachment.digest,
                        lastTransitDownloadAttemptTimestamp: nil,
                        localRelativeFilePath: pendingAttachment.localRelativeFilePath,
                        cachedAudioDurationSeconds: pendingAttachment.audioDurationSeconds,
                        cachedMediaHeightPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.height) },
                        cachedMediaWidthPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.width) },
                        cachedVideoDurationSeconds: pendingAttachment.videoDurationSeconds,
                        audioWaveformRelativeFilePath: pendingAttachment.audioWaveformRelativeFilePath,
                        videoStillFrameRelativeFilePath: pendingAttachment.videoStillFrameRelativeFilePath
                    )
                } else {
                    v2Attachment = TSAttachmentMigration.V2Attachment(
                        blurHash: oldAttachment.blurHash,
                        sha256ContentHash: nil,
                        encryptedByteCount: nil,
                        unencryptedByteCount: nil,
                        mimeType: oldAttachment.contentType,
                        encryptionKey: oldAttachment.encryptionKey ?? Cryptography.randomAttachmentEncryptionKey(),
                        digestSHA256Ciphertext: nil,
                        contentType: nil,
                        transitCdnNumber: oldAttachment.cdnNumber,
                        transitCdnKey: oldAttachment.cdnKey,
                        transitUploadTimestamp: oldAttachment.uploadTimestamp,
                        transitEncryptionKey: oldAttachment.encryptionKey,
                        transitUnencryptedByteCount: oldAttachment.byteCount,
                        transitDigestSHA256Ciphertext: oldAttachment.digest,
                        lastTransitDownloadAttemptTimestamp: nil,
                        localRelativeFilePath: pendingAttachment?.localRelativeFilePath,
                        cachedAudioDurationSeconds: nil,
                        cachedMediaHeightPixels: nil,
                        cachedMediaWidthPixels: nil,
                        cachedVideoDurationSeconds: nil,
                        audioWaveformRelativeFilePath: nil,
                        videoStillFrameRelativeFilePath: nil
                    )
                }

                try v2Attachment.insert(tx.database)
                v2AttachmentId = v2Attachment.id!
            }

            let mediaStoryOwnerType: UInt32 = 0
            let textStoryOwnerType: UInt32 = 1

            let ownerType: UInt32
            let captionBodyRanges: [TSAttachmentMigration.NSRangedValue<TSAttachmentMigration.CollapsedStyle>]?
            switch storyAttachment {
            case .file:
                ownerType = mediaStoryOwnerType
                captionBodyRanges = nil
            case .fileV2(let fileAttachment):
                ownerType = mediaStoryOwnerType
                captionBodyRanges = fileAttachment.captionStyles
            case .text(_):
                ownerType = textStoryOwnerType
                captionBodyRanges = nil
            case .foreignReferenceAttachment:
                return
            }

            let (sourceMediaHeightPixels, sourceMediaWidthPixels) = try oldAttachment.sourceMediaSizePixels() ?? (nil, nil)

            let reference = TSAttachmentMigration.StoryMessageAttachmentReference(
                ownerType: ownerType,
                ownerRowId: storyMessageRowId,
                attachmentRowId: v2AttachmentId,
                shouldLoop: renderingFlag == .shouldLoop,
                caption: oldAttachment.caption,
                captionBodyRanges: try captionBodyRanges.map { try JSONEncoder().encode($0) },
                sourceFilename: oldAttachment.sourceFilename,
                sourceUnencryptedByteCount: oldAttachment.byteCount,
                sourceMediaHeightPixels: sourceMediaHeightPixels,
                sourceMediaWidthPixels: sourceMediaWidthPixels
            )
            try reference.insert(tx.database)
        }
    }
}

extension TSAttachmentMigration.SerializedStoryMessageAttachment {

    var tsAttachmentUniqueId: String? {
        switch self {
        case .file(let attachmentId):
            return attachmentId
        case .text(let textAttachment):
            return textAttachment.preview?.imageAttachmentId
        case .fileV2(let attachment):
            return attachment.attachmentId
        case .foreignReferenceAttachment:
            return nil
        }
    }
}
