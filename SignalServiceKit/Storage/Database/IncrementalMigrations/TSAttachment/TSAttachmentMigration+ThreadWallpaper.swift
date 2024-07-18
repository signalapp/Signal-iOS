//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Migration for thread wallpapers, which were previously represented as an unencrypted
/// file on disk in a particular folder with the thread unique id as the file name.
/// After migrating they are full-fledged v2 attachments in the ThreadAttachmentReference table.
///
/// The migration works in two passes which must happen in separate write transactions but
/// must be run back to back. (Why? Filesystem changes are not part of the db transaction,
/// so we need to first "reserve" the final file location in the db and then write the file. If the latter
/// step fails we will just rewrite to the same file location next time we retry.)
///
/// Phase 1: Read the key value store for threads with image wallpapers, for each one create
/// a _new_ key value store entry with the "reserved" (random) final file location.
///
/// Phase 2: for each reserved file location, do image validation and create the v2 attachments.
/// Delete the originals.
extension TSAttachmentMigration {

    fileprivate static let legacyWallpaperDirectory = URL(
        fileURLWithPath: "Wallpapers",
        isDirectory: true,
        relativeTo: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup)!
    )

    /// First pass
    static func prepareThreadWallpaperMigration(tx: GRDBWriteTransaction) throws {
        let rows = try Row.fetchAll(
            tx.database,
            sql: "SELECT * FROM keyvalue WHERE collection = ?",
            arguments: ["Wallpaper+Enum"]
        )
        for row in rows {
            guard
                let valueData = row["value"] as? Data,
                let valueDecoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: valueData),
                valueDecoded == "photo",
                // Actually either thread unique id or "global";
                // we replicate that in our new entry.
                let threadUniqueId = row["key"] as? String
            else {
                continue
            }
            let reservedFileUUID = UUID().uuidString
            // Reinsert with the new collection name.
            try tx.database.execute(
                sql: """
                    INSERT INTO keyvalue
                     (collection, key, value)
                     VALUES (?, ?, ?)
                    """,
                arguments: ["WallpaperMigration", threadUniqueId, reservedFileUUID]
            )
        }
    }

    /// Second pass
    static func completeThreadWallpaperMigration(tx: GRDBWriteTransaction) throws {
        let reservedFileRows = try Row.fetchAll(
            tx.database,
            sql: "SELECT * FROM keyvalue WHERE collection = ?",
            arguments: ["WallpaperMigration"]
        )
        for row in reservedFileRows {
            guard
                let reservedFileUUIDRaw = row["value"] as? String,
                let reservedFileUUID = UUID(uuidString: reservedFileUUIDRaw),
                let threadUniqueIdOrGlobal = row["key"] as? String
            else {
                continue
            }
            // Nil for the global thread wallpaper.
            let threadRowId: Int64?
            let wallpaperFilename: String
            if threadUniqueIdOrGlobal == "global" {
                threadRowId = nil
                wallpaperFilename = "global"
            } else {
                guard
                    let fetchedThreadRowId = try Int64.fetchOne(
                        tx.database,
                        sql: "SELECT id FROM model_TSThread WHERE uniqueId = ?",
                        arguments: [threadUniqueIdOrGlobal]
                    ),
                    let filename = threadUniqueIdOrGlobal.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
                else {
                    continue
                }
                threadRowId = fetchedThreadRowId
                wallpaperFilename = filename
            }

            do {
                try Self.migrateSingleWallpaper(
                    reservedFileUUID: reservedFileUUID,
                    threadRowId: threadRowId,
                    wallpaperFilename: wallpaperFilename,
                    tx: tx
                )
            } catch {
                // Ignore failues on individual wallpapers; we'll just drop them if they're unable
                // to get migrated. But delete at the reserved file location just in case.
                try OWSFileSystem.deleteFileIfExists(
                    url: TSAttachmentMigration.V2Attachment.absoluteAttachmentFileURL(
                        relativeFilePath: TSAttachmentMigration.V2Attachment.relativeFilePath(reservedUUID: reservedFileUUID)
                    )
                )
            }
        }

        // Delete our reserved rows.
        try tx.database.execute(
            sql: "DELETE FROM keyvalue where collection = ?",
            arguments: ["WallpaperMigration"]
        )
    }

    // Delete the old wallpaper directory.
    static func cleanUpLegacyThreadWallpaperDirectory() throws {
        for filePath in try OWSFileSystem.recursiveFilesInDirectory(legacyWallpaperDirectory.path) {
            if !OWSFileSystem.deleteFile(filePath, ignoreIfMissing: true) {
                throw OWSAssertionError("Failed to delete!")
            }
        }
    }

    private static func migrateSingleWallpaper(
        reservedFileUUID: UUID,
        threadRowId: Int64?,
        wallpaperFilename: String,
        tx: GRDBWriteTransaction
    ) throws {
        let wallpaperFile = URL(
            fileURLWithPath: wallpaperFilename,
            isDirectory: false,
            relativeTo: legacyWallpaperDirectory
        )

        let reservedFileIds = TSAttachmentMigration.V2AttachmentContentValidator.ReservedRelativeFileIds(
            primaryFile: reservedFileUUID,
            audioWaveform: UUID() /* unused */,
            videoStillFrame: UUID() /* unused */
        )

        let pendingAttachment: TSAttachmentMigration.PendingV2AttachmentFile
        do {
            pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.validateContents(
                unencryptedFileUrl: wallpaperFile,
                reservedFileIds: reservedFileIds,
                encryptionKey: nil,
                mimeType: "image/jpeg",
                renderingFlag: .default,
                sourceFilename: nil
            )
        } catch {
            guard
                let imageData = try? Data(contentsOf: wallpaperFile),
                let image = UIImage(data: imageData),
                let resizedImage = image.resized(maxDimensionPixels: CGFloat(TSAttachmentMigration.kMaxStillImageDimensions)),
                let resizedImageData = resizedImage.jpegData(compressionQuality: 0.8)
            else {
                // We can't get the image to resize.
                // Just drop it; the wallpaper will be lost.
                return
            }

            // Try again with a resized image.
            let resizedImageFile = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            try resizedImageData.write(to: resizedImageFile)
            pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.validateContents(
                unencryptedFileUrl: resizedImageFile,
                reservedFileIds: reservedFileIds,
                encryptionKey: nil,
                mimeType: "image/jpeg",
                renderingFlag: .default,
                sourceFilename: nil
            )
        }

        let v2AttachmentId: Int64
        if
            let existingV2Attachment = try TSAttachmentMigration.V2Attachment
                .filter(Column("sha256ContentHash") == pendingAttachment.sha256ContentHash)
                .fetchOne(tx.database)
        {
            // If we already have a v2 attachment with the same plaintext hash,
            // create new references to it and drop the pending attachment.
            v2AttachmentId = existingV2Attachment.id!
            // Delete the reserved files being used by the pending attachment.
            try OWSFileSystem.deleteFileIfExists(
                url: TSAttachmentMigration.V2Attachment.absoluteAttachmentFileURL(
                    relativeFilePath: TSAttachmentMigration.V2Attachment.relativeFilePath(
                        reservedUUID: reservedFileUUID
                    )
                )
            )
        } else {
            var v2Attachment = TSAttachmentMigration.V2Attachment(
                blurHash: pendingAttachment.blurHash,
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                encryptedByteCount: pendingAttachment.encryptedByteCount,
                unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                mimeType: pendingAttachment.mimeType,
                encryptionKey: pendingAttachment.encryptionKey,
                digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                contentType: UInt32(pendingAttachment.validatedContentType.rawValue),
                transitCdnNumber: nil,
                transitCdnKey: nil,
                transitUploadTimestamp: nil,
                transitEncryptionKey: nil,
                transitUnencryptedByteCount: nil,
                transitDigestSHA256Ciphertext: nil,
                lastTransitDownloadAttemptTimestamp: nil,
                localRelativeFilePath: pendingAttachment.localRelativeFilePath,
                cachedAudioDurationSeconds: pendingAttachment.audioDurationSeconds,
                cachedMediaHeightPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.height) },
                cachedMediaWidthPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.width) },
                cachedVideoDurationSeconds: pendingAttachment.videoDurationSeconds,
                audioWaveformRelativeFilePath: pendingAttachment.audioWaveformRelativeFilePath,
                videoStillFrameRelativeFilePath: pendingAttachment.videoStillFrameRelativeFilePath
            )

            try v2Attachment.insert(tx.database)
            v2AttachmentId = v2Attachment.id!
        }

        let reference = TSAttachmentMigration.ThreadAttachmentReference(
            ownerRowId: threadRowId,
            attachmentRowId: v2AttachmentId,
            creationTimestamp: Date().ows_millisecondsSince1970
        )
        try reference.insert(tx.database)
    }
}
