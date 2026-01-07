//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class AttachmentManagerImpl: AttachmentManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let dateProvider: DateProvider
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    private let orphanedAttachmentStore: OrphanedAttachmentStore
    private let orphanedBackupAttachmentScheduler: OrphanedBackupAttachmentScheduler
    private let remoteConfigManager: RemoteConfigManager
    private let stickerManager: Shims.StickerManager

    public init(
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentStore: AttachmentStore,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        dateProvider: @escaping DateProvider,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        orphanedBackupAttachmentScheduler: OrphanedBackupAttachmentScheduler,
        remoteConfigManager: RemoteConfigManager,
        stickerManager: Shims.StickerManager,
    ) {
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
        self.dateProvider = dateProvider
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.orphanedAttachmentStore = orphanedAttachmentStore
        self.orphanedBackupAttachmentScheduler = orphanedBackupAttachmentScheduler
        self.remoteConfigManager = remoteConfigManager
        self.stickerManager = stickerManager
    }

    // MARK: - Public

    // MARK: Creating Attachments from source

    public func createAttachmentPointer(
        from ownedProto: OwnedAttachmentPointerProto,
        tx: DBWriteTransaction,
    ) throws {
        let sanitizedOwnedProto = OwnedAttachmentPointerProto(
            proto: ownedProto.proto,
            owner: sanitizeOversizeTextOwner(
                currentOwner: ownedProto.owner,
                mimeType: ownedProto.proto.contentType ?? "",
            ),
        )

        try _createAttachmentPointer(
            from: sanitizedOwnedProto.proto,
            owner: sanitizedOwnedProto.owner,
            tx: tx,
        )
    }

    public func createAttachmentPointer(
        from ownedBackupProto: OwnedAttachmentBackupPointerProto,
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction,
    ) -> OwnedAttachmentBackupPointerProto.CreationError? {
        let sanitizedOwnedBackupProto = OwnedAttachmentBackupPointerProto(
            proto: ownedBackupProto.proto,
            renderingFlag: ownedBackupProto.renderingFlag,
            clientUUID: ownedBackupProto.clientUUID,
            owner: sanitizeOversizeTextOwner(
                currentOwner: ownedBackupProto.owner,
                mimeType: ownedBackupProto.proto.contentType,
            ),
        )

        switch _createAttachmentPointer(
            from: sanitizedOwnedBackupProto,
            uploadEra: uploadEra,
            attachmentByteCounter: attachmentByteCounter,
            tx: tx,
        ) {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }

    public func createAttachmentStream(
        from ownedDataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction,
    ) throws {
        let sanitizedOwnedDataSource = OwnedAttachmentDataSource(
            dataSource: ownedDataSource.source,
            owner: sanitizeOversizeTextOwner(
                currentOwner: ownedDataSource.owner,
                mimeType: ownedDataSource.mimeType,
            ),
        )

        try _createAttachmentStream(
            from: sanitizedOwnedDataSource,
            tx: tx,
        )

        // When we create the attachment streams we schedule a backup of the
        // new attachments. Kick the tires so that upload starts happening now.
        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
        }
    }

    public func updateAttachmentWithOversizeTextFromBackup(
        attachmentId: Attachment.IDType,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction,
    ) throws {
        guard let attachment = attachmentStore.fetch(id: attachmentId, tx: tx) else {
            // The attachment got deleted? Should be impossible but ultimately fine.
            return
        }

        if attachment.asStream() != nil {
            // Its already a stream? Should be impossible but ultimately fine.
            return
        }

        try _updateAttachmentWithOversizeTextFromBackup(
            attachment: attachment,
            pendingAttachment: pendingAttachment,
            tx: tx,
        )
    }

    // MARK: Quoted Replies

    public func createQuotedReplyMessageThumbnail(
        from quotedReplyAttachmentDataSource: QuotedReplyAttachmentDataSource,
        owningMessageAttachmentBuilder: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder,
        tx: DBWriteTransaction,
    ) throws {
        try _createQuotedReplyMessageThumbnail(
            dataSource: quotedReplyAttachmentDataSource,
            referenceOwner: .quotedReplyAttachment(owningMessageAttachmentBuilder),
            tx: tx,
        )
    }

    // MARK: - Helpers

    private typealias OwnerId = AttachmentReference.OwnerId
    private typealias OwnerBuilder = AttachmentReference.OwnerBuilder

    // MARK: Creating Attachments from source

    private func sanitizeOversizeTextOwner(
        currentOwner: OwnerBuilder,
        mimeType: String,
    ) -> OwnerBuilder {
        if
            mimeType == MimeType.textXSignalPlain.rawValue,
            case .messageBodyAttachment(let metadata) = currentOwner
        {
            return .messageOversizeText(.init(
                messageRowId: metadata.messageRowId,
                receivedAtTimestamp: metadata.receivedAtTimestamp,
                threadRowId: metadata.threadRowId,
                isPastEditRevision: metadata.isPastEditRevision,
            ))
        } else {
            return currentOwner
        }
    }

    private func _createAttachmentPointer(
        from proto: SSKProtoAttachmentPointer,
        owner: OwnerBuilder,
        tx: DBWriteTransaction,
    ) throws {
        let transitTierInfo = try self.transitTierInfo(from: proto)

        let knownIdFromProto: OwnerBuilder.KnownIdInOwner = {
            if
                let uuidData = proto.clientUuid,
                let uuid = UUID(data: uuidData)
            {
                return .known(uuid)
            } else {
                return .knownNil
            }
        }()

        let sourceFilename = proto.fileName
        let mimeType = self.mimeType(
            fromProtoContentType: proto.contentType,
            sourceFilename: sourceFilename,
        )

        let attachmentParams = Attachment.ConstructionParams.fromPointer(
            blurHash: proto.blurHash,
            mimeType: mimeType,
            encryptionKey: transitTierInfo.encryptionKey,
            latestTransitTierInfo: transitTierInfo,
        )
        let sourceMediaSizePixels: CGSize?
        if
            proto.width > 0,
            let width = CGFloat(exactly: proto.width),
            proto.height > 0,
            let height = CGFloat(exactly: proto.height)
        {
            sourceMediaSizePixels = CGSize(width: width, height: height)
        } else {
            sourceMediaSizePixels = nil
        }

        let referenceParams = AttachmentReference.ConstructionParams(
            owner: try owner.build(
                knownIdInOwner: knownIdFromProto,
                renderingFlag: .fromProto(proto),
                // Not downloaded so we don't know the content type.
                contentType: nil,
                // This should be unset for newly-incoming attachments, but it's
                // still technically in the proto definition.
                caption: proto.hasCaption ? proto.caption : nil,
            ),
            sourceFilename: sourceFilename,
            sourceUnencryptedByteCount: proto.size,
            sourceMediaSizePixels: sourceMediaSizePixels,
        )

        try attachmentStore.insert(
            attachmentParams,
            reference: referenceParams,
            tx: tx,
        )

        if let mediaName = attachmentParams.mediaName {
            orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                withMediaName: mediaName,
                tx: tx,
            )
        }

        switch referenceParams.owner {
        case .message(.sticker(let stickerInfo)):
            // Only for stickers, schedule a high priority "download"
            // from the local sticker pack if we have it.
            let installedSticker = self.stickerManager.fetchInstalledSticker(
                packId: stickerInfo.stickerPackId,
                stickerId: stickerInfo.stickerId,
                tx: tx,
            )
            if installedSticker != nil {
                guard
                    let newAttachmentReference = attachmentStore.fetchAnyReference(
                        owner: referenceParams.owner.id,
                        tx: tx,
                    )
                else {
                    throw OWSAssertionError("Missing attachment we just created")
                }
                attachmentDownloadManager.enqueueDownloadOfAttachment(
                    id: newAttachmentReference.attachmentRowId,
                    priority: .localClone,
                    source: .transitTier,
                    tx: tx,
                )
            }
        default:
            break
        }
    }

    private func transitTierInfo(
        from proto: SSKProtoAttachmentPointer,
    ) throws -> Attachment.TransitTierInfo {
        let cdnNumber = proto.cdnNumber
        guard let cdnKey = proto.cdnKey?.nilIfEmpty, cdnNumber > 0 else {
            throw OWSAssertionError("Invalid cdn info")
        }
        guard let encryptionKey = proto.key?.nilIfEmpty else {
            throw OWSAssertionError("Invalid encryption key")
        }
        guard let digestSHA256Ciphertext = proto.digest?.nilIfEmpty else {
            throw OWSAssertionError("Missing digest")
        }

        return .init(
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            uploadTimestamp: proto.uploadTimestamp,
            encryptionKey: encryptionKey,
            unencryptedByteCount: proto.size,
            integrityCheck: .digestSHA256Ciphertext(digestSHA256Ciphertext),
            // TODO: [Attachment Streaming] Extract incremental MAC info from the attachment pointer.
            incrementalMacInfo: nil,
            lastDownloadAttemptTimestamp: nil,
        )
    }

    private func _createAttachmentPointer(
        from ownedProto: OwnedAttachmentBackupPointerProto,
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction,
    ) -> Result<Void, OwnedAttachmentBackupPointerProto.CreationError> {
        let proto = ownedProto.proto

        let knownIdFromProto = ownedProto.clientUUID.map {
            return OwnerBuilder.KnownIdInOwner.known($0)
        } ?? .knownNil

        let sourceFilename = proto.fileName.nilIfEmpty
        let mimeType = self.mimeType(
            fromProtoContentType: proto.contentType,
            sourceFilename: sourceFilename,
        )

        let sourceMediaSizePixels: CGSize?
        if
            proto.width > 0,
            let width = CGFloat(exactly: proto.width),
            proto.height > 0,
            let height = CGFloat(exactly: proto.height)
        {
            sourceMediaSizePixels = CGSize(width: width, height: height)
        } else {
            sourceMediaSizePixels = nil
        }

        // This is defined on the FilePointer outside the locator,
        // but applies to either the media tier upload or the transit
        // tier upload, whichever is available. (Or both! If both are
        // available they both are the same encrypted blob.)
        let incrementalMacInfo: Attachment.IncrementalMacInfo?
        if
            proto.hasIncrementalMac,
            proto.hasIncrementalMacChunkSize
        {
            // Incremental mac is unsupported on iOS;
            // when we add support and can validate at
            // download time, we should pull it off the proto.
            incrementalMacInfo = nil
        } else {
            incrementalMacInfo = nil
        }

        let attachmentParams: Attachment.ConstructionParams
        let sourceUnencryptedByteCount: UInt32?

        if
            proto.hasLocatorInfo,
            let encryptionKey = proto.locatorInfo.key.nilIfEmpty
        {
            let transitTierInfo = self.transitTierInfo(
                from: proto.locatorInfo,
                owningMessageReceivedAtTimestamp: ownedProto.owningMessageReceivedAtTimestamp,
                incrementalMacInfo: incrementalMacInfo,
            )

            if proto.locatorInfo.size > 0 {
                sourceUnencryptedByteCount = proto.locatorInfo.size
            } else {
                sourceUnencryptedByteCount = nil
            }

            switch proto.locatorInfo.integrityCheck {
            case .plaintextHash(let sha256ContentHash):
                if sha256ContentHash.isEmpty {
                    fallthrough
                }
                let mediaTierCdnNumber = proto.locatorInfo.hasMediaTierCdnNumber ? proto.locatorInfo.mediaTierCdnNumber : nil
                attachmentParams = .fromBackup(
                    blurHash: proto.blurHash.nilIfEmpty,
                    mimeType: mimeType,
                    encryptionKey: encryptionKey,
                    latestTransitTierInfo: transitTierInfo,
                    sha256ContentHash: sha256ContentHash,
                    mediaName: Attachment.mediaName(
                        sha256ContentHash: sha256ContentHash,
                        encryptionKey: encryptionKey,
                    ),
                    mediaTierInfo: .init(
                        cdnNumber: mediaTierCdnNumber,
                        unencryptedByteCount: proto.locatorInfo.size,
                        sha256ContentHash: sha256ContentHash,
                        incrementalMacInfo: incrementalMacInfo,
                        uploadEra: uploadEra,
                        lastDownloadAttemptTimestamp: nil,
                    ),
                    thumbnailMediaTierInfo: .init(
                        // Assume the thumbnail uses the same cdn as fullsize;
                        // this _can_ go wrong if the server changes cdns between
                        // the two uploads but worst case we lose the thumbnail.
                        cdnNumber: mediaTierCdnNumber,
                        uploadEra: uploadEra,
                        lastDownloadAttemptTimestamp: nil,
                    ),
                )
            case .encryptedDigest, .none:
                if let transitTierInfo {
                    attachmentParams = .fromBackup(
                        blurHash: proto.blurHash.nilIfEmpty,
                        mimeType: mimeType,
                        encryptionKey: encryptionKey,
                        latestTransitTierInfo: transitTierInfo,
                        sha256ContentHash: nil,
                        mediaName: nil,
                        mediaTierInfo: nil,
                        thumbnailMediaTierInfo: nil,
                    )
                } else {
                    attachmentParams = .forInvalidBackupAttachment(
                        blurHash: proto.blurHash.nilIfEmpty,
                        mimeType: mimeType,
                    )
                }
            }
        } else {
            attachmentParams = .forInvalidBackupAttachment(
                blurHash: proto.blurHash.nilIfEmpty,
                mimeType: mimeType,
            )
            sourceUnencryptedByteCount = nil
        }

        let referenceParams: AttachmentReference.ConstructionParams
        do {
            referenceParams = AttachmentReference.ConstructionParams(
                owner: try ownedProto.owner.build(
                    knownIdInOwner: knownIdFromProto,
                    renderingFlag: ownedProto.renderingFlag,
                    // Not downloaded so we don't know the content type.
                    contentType: nil,
                    // Restored legacy attachments might have a caption.
                    caption: proto.hasCaption ? proto.caption : nil,
                ),
                sourceFilename: sourceFilename,
                sourceUnencryptedByteCount: sourceUnencryptedByteCount,
                sourceMediaSizePixels: sourceMediaSizePixels,
            )
        } catch {
            return .failure(.dbInsertionError(error))
        }

        do {
            let attachmentRowId = try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx,
            )

            if let sourceUnencryptedByteCount {
                attachmentByteCounter.addToByteCount(
                    attachmentID: attachmentRowId,
                    byteCount: Cryptography.estimatedMediaTierCDNSize(unencryptedSize: UInt64(safeCast: sourceUnencryptedByteCount)) ?? UInt64(UInt32.max),
                )
            }

            if let mediaName = attachmentParams.mediaName {
                orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                    withMediaName: mediaName,
                    tx: tx,
                )
            }

            return .success(())
        } catch let error as AttachmentInsertError {
            switch error {
            case .duplicatePlaintextHash(let existingAttachmentId):
                // Ideally, exporting clients would dedupe by plaintext hash, merging
                // any duplicates so every copy with the same plaintext hash in the
                // backup also has the same encryption key (and therefore same mediaName).
                // However, there have been bugs where this is not the case. We can treat
                // duplicate plaintext hashes the same as duplicate media name (point the
                // duplicate to the first attachment), but this does drop cdn info if,
                // for example, this copy had valid cdn info and the older one did not.
                // It is on the exporter to dedupe and merge as needed so this doesn't happen.
                fallthrough
            case .duplicateMediaName(let existingAttachmentId):
                // We already have an attachment with the same mediaName (likely from this same
                // backup). Just point the reference at the existing attachment.
                do {
                    try attachmentStore.addOwner(
                        referenceParams,
                        for: existingAttachmentId,
                        tx: tx,
                    )
                    return .success(())
                } catch {
                    return .failure(.dbInsertionError(error))
                }
            }
        } catch {
            return .failure(.dbInsertionError(error))
        }
    }

    private func transitTierInfo(
        from locatorInfo: BackupProto_FilePointer.LocatorInfo,
        owningMessageReceivedAtTimestamp: UInt64?,
        incrementalMacInfo: Attachment.IncrementalMacInfo?,
    ) -> Attachment.TransitTierInfo? {
        guard locatorInfo.key.count > 0 else { return nil }

        guard locatorInfo.transitCdnKey.isEmpty.negated else {
            // Ok to be missing transit-tier CDN info on a backup locator, if
            // this attachment was never uploaded.
            return nil
        }

        let unencryptedByteCount: UInt32?
        if locatorInfo.size > 0 {
            unencryptedByteCount = locatorInfo.size
        } else {
            unencryptedByteCount = nil
        }

        let uploadTimestampMs: UInt64
        if locatorInfo.hasTransitTierUploadTimestamp, locatorInfo.transitTierUploadTimestamp > 0 {
            uploadTimestampMs = locatorInfo.transitTierUploadTimestamp
        } else if let owningMessageReceivedAtTimestamp {
            // iOS historically did not set the `uploadTimestamp` on attachment
            // protos we sent with outgoing messages. As a workaround for our
            // purposes here, we'll sub in the `receivedAt` timestamp for the
            // message this attachment is owned by (if applicable).
            uploadTimestampMs = owningMessageReceivedAtTimestamp
        } else {
            uploadTimestampMs = 0
        }

        let integrityCheck: AttachmentIntegrityCheck
        switch locatorInfo.integrityCheck {
        case .plaintextHash(let data):
            guard !data.isEmpty else {
                return nil
            }
            integrityCheck = .sha256ContentHash(data)
        case .encryptedDigest(let data):
            guard !data.isEmpty else {
                return nil
            }
            integrityCheck = .digestSHA256Ciphertext(data)
        case .none:
            return nil
        }

        return Attachment.TransitTierInfo(
            cdnNumber: locatorInfo.transitCdnNumber,
            cdnKey: locatorInfo.transitCdnKey,
            uploadTimestamp: uploadTimestampMs,
            encryptionKey: locatorInfo.key,
            unencryptedByteCount: unencryptedByteCount,
            integrityCheck: integrityCheck,
            incrementalMacInfo: incrementalMacInfo,
            lastDownloadAttemptTimestamp: nil,
        )
    }

    private func mimeType(
        fromProtoContentType contentType: String?,
        sourceFilename: String?,
    ) -> String {
        if let protoMimeType = contentType?.nilIfEmpty {
            return protoMimeType
        } else {
            // Content type might not set if the sending client can't
            // infer a MIME type from the file extension.
            if
                let sourceFilename,
                let fileExtension = (sourceFilename as NSString).pathExtension.lowercased().nilIfEmpty,
                let inferredMimeType = MimeTypeUtil.mimeTypeForFileExtension(fileExtension)?.nilIfEmpty
            {
                Logger.warn("Missing attachment content type! Inferred MIME type: \(inferredMimeType)")
                return inferredMimeType
            } else {
                Logger.warn("Missing attachment content type! Failed to infer MIME type, falling back to octet-stream.")
                return MimeType.applicationOctetStream.rawValue
            }
        }
    }

    private func _createAttachmentStream(
        from ownedDataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction,
    ) throws {
        switch ownedDataSource.source {
        case .existingAttachment(let existingAttachmentMetadata):
            guard let existingAttachment = attachmentStore.fetch(id: existingAttachmentMetadata.id, tx: tx) else {
                throw OWSAssertionError("Missing existing attachment!")
            }

            let owner: AttachmentReference.Owner = try ownedDataSource.owner.build(
                knownIdInOwner: .none,
                renderingFlag: existingAttachmentMetadata.renderingFlag,
                contentType: existingAttachment.streamInfo?.contentType.raw,
            )
            let referenceParams = AttachmentReference.ConstructionParams(
                owner: owner,
                sourceFilename: existingAttachmentMetadata.sourceFilename,
                sourceUnencryptedByteCount: existingAttachmentMetadata.sourceUnencryptedByteCount,
                sourceMediaSizePixels: existingAttachmentMetadata.sourceMediaSizePixels,
            )
            try attachmentStore.addOwner(
                referenceParams,
                for: existingAttachment.id,
                tx: tx,
            )
        case .pendingAttachment(let pendingAttachment):
            let owner: AttachmentReference.Owner = try ownedDataSource.owner.build(
                knownIdInOwner: .none,
                renderingFlag: pendingAttachment.renderingFlag,
                contentType: pendingAttachment.validatedContentType.raw,
            )
            let mediaSizePixels: CGSize?
            switch pendingAttachment.validatedContentType {
            case .invalid, .file, .audio:
                mediaSizePixels = nil
            case .image(let pixelSize), .video(_, let pixelSize, _), .animatedImage(let pixelSize):
                mediaSizePixels = pixelSize
            }
            let referenceParams = AttachmentReference.ConstructionParams(
                owner: owner,
                sourceFilename: pendingAttachment.sourceFilename,
                sourceUnencryptedByteCount: pendingAttachment.unencryptedByteCount,
                sourceMediaSizePixels: mediaSizePixels,
            )
            let mediaName = Attachment.mediaName(
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                encryptionKey: pendingAttachment.encryptionKey,
            )
            let streamInfo = Attachment.StreamInfo(
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                mediaName: mediaName,
                encryptedByteCount: pendingAttachment.encryptedByteCount,
                unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                contentType: pendingAttachment.validatedContentType,
                digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                localRelativeFilePath: pendingAttachment.localRelativeFilePath,
            )
            let attachmentParams = Attachment.ConstructionParams.fromStream(
                blurHash: pendingAttachment.blurHash,
                mimeType: pendingAttachment.mimeType,
                encryptionKey: pendingAttachment.encryptionKey,
                streamInfo: streamInfo,
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                mediaName: mediaName,
            )

            let hasOrphanRecord = orphanedAttachmentStore.orphanAttachmentExists(
                with: pendingAttachment.orphanRecordId,
                tx: tx,
            )

            do {
                let hasExistingAttachmentWithSameFile = attachmentStore.fetchAttachment(
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    tx: tx,
                )?.streamInfo?.localRelativeFilePath == pendingAttachment.localRelativeFilePath

                // Typically, we'd expect an orphan record to exist (which ensures that
                // if this creation transaction fails, the file on disk gets cleaned up).
                // However, in AttachmentMultisend we send the same pending attachment file multiple
                // times; the first instance creates an attachment and deletes the orphan record.
                // We can detect this (and know its ok) if the existing attachment uses the same file
                // as our pending attachment; that only happens if it shared the pending attachment.
                guard hasExistingAttachmentWithSameFile || hasOrphanRecord else {
                    throw OWSAssertionError("Attachment file deleted before creation")
                }

                // Try and insert the new attachment.
                try attachmentStore.insert(
                    attachmentParams,
                    reference: referenceParams,
                    tx: tx,
                )
                if hasOrphanRecord {
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)
                }
                if let mediaName = attachmentParams.mediaName {
                    orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                        withMediaName: mediaName,
                        tx: tx,
                    )

                    if
                        let attachment = attachmentStore.fetchAttachment(
                            mediaName: mediaName,
                            tx: tx,
                        )
                    {
                        backupAttachmentUploadScheduler.enqueueIfNeededWithOwner(
                            attachment,
                            owner: owner,
                            tx: tx,
                        )
                    }
                }
            } catch let error {
                let existingAttachmentId: Attachment.IDType
                if let error = error as? AttachmentInsertError {
                    existingAttachmentId = try Self.handleAttachmentInsertError(
                        error,
                        newAttachmentOwner: owner,
                        pendingAttachmentStreamInfo: streamInfo,
                        pendingAttachmentEncryptionKey: pendingAttachment.encryptionKey,
                        pendingAttachmentMimeType: pendingAttachment.mimeType,
                        pendingAttachmentOrphanRecordId: hasOrphanRecord ? pendingAttachment.orphanRecordId : nil,
                        pendingAttachmentLatestTransitTierInfo: attachmentParams.latestTransitTierInfo,
                        pendingAttachmentOriginalTransitTierInfo: attachmentParams.originalTransitTierInfo,
                        attachmentStore: attachmentStore,
                        orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                        orphanedAttachmentStore: orphanedAttachmentStore,
                        backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                        orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
                        tx: tx,
                    )
                } else {
                    throw error
                }

                // Already have an attachment with the same plaintext hash or media name! Create a new reference to it instead.
                // If this fails and throws, the database won't be in an invalid state even if not rolled
                // back; the existing attachment just doesn't get its new owner.
                try attachmentStore.addOwner(
                    referenceParams,
                    for: existingAttachmentId,
                    tx: tx,
                )
                return
            }
        }
    }

    private func _updateAttachmentWithOversizeTextFromBackup(
        attachment: Attachment,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction,
    ) throws {
        let mediaName = Attachment.mediaName(
            sha256ContentHash: pendingAttachment.sha256ContentHash,
            encryptionKey: pendingAttachment.encryptionKey,
        )
        let streamInfo = Attachment.StreamInfo(
            sha256ContentHash: pendingAttachment.sha256ContentHash,
            mediaName: mediaName,
            encryptedByteCount: pendingAttachment.encryptedByteCount,
            unencryptedByteCount: pendingAttachment.unencryptedByteCount,
            contentType: pendingAttachment.validatedContentType,
            digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
            localRelativeFilePath: pendingAttachment.localRelativeFilePath,
        )

        do {
            guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                throw OWSAssertionError("Attachment file deleted before creation")
            }

            // Update the placeholder attachment we previously created with the stream info
            try self.attachmentStore.updateAttachmentAsDownloaded(
                // Not technically true but close enough.
                from: .mediaTierFullsize,
                priority: .backupRestore,
                id: attachment.id,
                validatedMimeType: pendingAttachment.mimeType,
                streamInfo: streamInfo,
                // This is used for "last viewed" state which isn't used
                // for oversize text so it doesn't really matter but give
                // a real date anyway.
                timestamp: dateProvider().ows_millisecondsSince1970,
                tx: tx,
            )
            // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
            self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

            // Normally, after we create a stream, we schedule it for media tier upload, remove any
            // media tier deletion jobs, etc. But we don't back up oversize text to media tier (since
            // we inline it) so we don't need to do any of that.

        } catch let error as AttachmentInsertError {
            let existingAttachmentId: Attachment.IDType
            switch error {
            case .duplicatePlaintextHash(let id):
                existingAttachmentId = id
            case .duplicateMediaName(let id):
                owsFailDebug("How did we match mediaName when using a random encryption key?")
                existingAttachmentId = id
            }

            // Already have an attachment with the same plaintext hash or media name!
            // Move all existing references to that copy, instead.
            // Doing so should delete the original attachment pointer.
            // This happens if we have two instances of the same oversized text
            // in the backup (e.g. some long text message was forwarded)

            // Just hold all refs in memory; there shouldn't in practice be
            // so many pointers to the same attachment.
            var references = [AttachmentReference]()
            self.attachmentStore.enumerateAllReferences(
                toAttachmentId: attachment.id,
                tx: tx,
            ) { reference, _ in
                references.append(reference)
            }
            try references.forEach { reference in
                try self.attachmentStore.removeOwner(
                    reference: reference,
                    tx: tx,
                )
                let newOwnerParams = AttachmentReference.ConstructionParams(
                    owner: reference.owner.forReassignmentWithContentType(pendingAttachment.validatedContentType.raw),
                    sourceFilename: reference.sourceFilename,
                    sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                    sourceMediaSizePixels: reference.sourceMediaSizePixels,
                )
                try self.attachmentStore.addOwner(
                    newOwnerParams,
                    for: existingAttachmentId,
                    tx: tx,
                )
            }
        }
    }

    /// When inserting an attachment stream (or updating an existing attachment to a stream),
    /// handle errors due to collisions with existing attachments' mediaName or plaintext hash.
    /// Returns the collided attachment's id, which should be used as the attachment id thereafter.
    ///
    /// - parameter newAttachmentOwner: If nil, will fetch all owning references for media tier (backup)
    /// upload eligibility checking.
    /// If non-nil, will be used exclusively to determine upload eligibility, ignoring any other owning references
    /// that may exist. This is okay when creating a single new reference and assuming the attachment would
    /// have already been scheduled for upload had existing references made it eligible.
    static func handleAttachmentInsertError(
        _ error: AttachmentInsertError,
        newAttachmentOwner: AttachmentReference.Owner? = nil,
        pendingAttachmentStreamInfo: Attachment.StreamInfo,
        pendingAttachmentEncryptionKey: Data,
        pendingAttachmentMimeType: String,
        pendingAttachmentOrphanRecordId: OrphanedAttachmentRecord.RowId?,
        pendingAttachmentLatestTransitTierInfo: Attachment.TransitTierInfo?,
        pendingAttachmentOriginalTransitTierInfo: Attachment.TransitTierInfo?,
        attachmentStore: AttachmentStore,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        orphanedBackupAttachmentScheduler: OrphanedBackupAttachmentScheduler,
        tx: DBWriteTransaction,
    ) throws -> Attachment.IDType {
        let existingAttachmentId: Attachment.IDType
        switch error {
        case
            .duplicatePlaintextHash(let id),
            .duplicateMediaName(let id):
            existingAttachmentId = id
        }

        guard let existingAttachment = attachmentStore.fetch(id: existingAttachmentId, tx: tx) else {
            throw OWSAssertionError("Matched attachment missing")
        }

        guard existingAttachment.asStream() == nil else {
            // If we already have a stream, we should leave it untouched,
            // and leave the orphan record around for the new pending
            // attachment so that its files get deleted.
            return existingAttachmentId
        }

        // If we have a mediaName match, then we can keep the existing media tier
        // info. Otherwise we had a plaintext hash collision but with a different
        // encryption key. Because the new copy has a downloaded file and the old
        // copy does not, we prefer the new copy even though that means we will
        // now orphan the old media tier upload.
        // Note the same doesn't apply to transit tier and we always keep the existing
        // transit tier upload information. Unlike media tier uploads, transit tier
        // uploads are not required to use the same stable encryption key as the
        // local stream metadata, so its okay if we swap out the local encryption key.
        let mediaTierInfo: Attachment.MediaTierInfo?
        let thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?
        if pendingAttachmentStreamInfo.mediaName == existingAttachment.mediaName {
            mediaTierInfo = existingAttachment.mediaTierInfo
            thumbnailMediaTierInfo = existingAttachment.thumbnailMediaTierInfo
        } else {
            mediaTierInfo = nil
            thumbnailMediaTierInfo = nil

            // Orphan the existing remote upload, both fullsize and thumbnail.
            // We're using a new encryption key now which means a new mediaName.
            try orphanedBackupAttachmentScheduler.orphanExistingMediaTierUploads(
                of: existingAttachment,
                tx: tx,
            )

            // Orphan the local thumbnail file, if the attachment had one, since
            // we now use a different encryption key and we don't keep thumbnails
            // when we have a stream, anyway.
            if let thumbnailRelativeFilePath = existingAttachment.localRelativeFilePathThumbnail {
                _ = OrphanedAttachmentRecord.insertRecord(
                    OrphanedAttachmentRecord.InsertableRecord(
                        isPendingAttachment: false,
                        localRelativeFilePath: nil,
                        localRelativeFilePathThumbnail: thumbnailRelativeFilePath,
                        localRelativeFilePathAudioWaveform: nil,
                        localRelativeFilePathVideoStillFrame: nil,
                    ),
                    tx: tx,
                )
            }
        }

        // Transit tier info has its own key independent of the local file encryption key;
        // we should just keep whichever upload we think is newer.
        let latestTransitTierInfo: Attachment.TransitTierInfo?
        if
            let existingTransitTierInfo = existingAttachment.latestTransitTierInfo,
            let pendingAttachmentLatestTransitTierInfo
        {
            if existingTransitTierInfo.uploadTimestamp > pendingAttachmentLatestTransitTierInfo.uploadTimestamp {
                latestTransitTierInfo = existingTransitTierInfo
            } else {
                latestTransitTierInfo = pendingAttachmentLatestTransitTierInfo
            }
        } else {
            // Take whichever one we've got.
            latestTransitTierInfo = existingAttachment.latestTransitTierInfo ?? pendingAttachmentLatestTransitTierInfo
        }

        // Original transit tier info must match the top level encryption key and digest.
        // We will take any candidate transit tier info that meets those requirements.
        var originalTransitTierInfo: Attachment.TransitTierInfo?
        let candidateOriginalTransitTierInfos = [
            existingAttachment.latestTransitTierInfo,
            existingAttachment.originalTransitTierInfo,
            pendingAttachmentLatestTransitTierInfo,
            pendingAttachmentOriginalTransitTierInfo,
        ].compacted()
        for candidateOriginalTransitTierInfo in candidateOriginalTransitTierInfos {
            guard candidateOriginalTransitTierInfo.encryptionKey == pendingAttachmentEncryptionKey else {
                continue
            }
            switch candidateOriginalTransitTierInfo.integrityCheck {
            case .sha256ContentHash:
                // Can't verify the digest (and iv) match, so we can't use this one.
                continue
            case .digestSHA256Ciphertext(let infoDigest):
                if
                    infoDigest == pendingAttachmentStreamInfo.digestSHA256Ciphertext,
                    originalTransitTierInfo == nil
                    || originalTransitTierInfo!.uploadTimestamp
                    < candidateOriginalTransitTierInfo.uploadTimestamp
                {
                    originalTransitTierInfo = candidateOriginalTransitTierInfo
                }
            }

        }

        // Set the stream info on the existing attachment, if needed.
        try attachmentStore.merge(
            streamInfo: pendingAttachmentStreamInfo,
            into: existingAttachment,
            encryptionKey: pendingAttachmentEncryptionKey,
            validatedMimeType: pendingAttachmentMimeType,
            latestTransitTierInfo: latestTransitTierInfo,
            originalTransitTierInfo: originalTransitTierInfo,
            mediaTierInfo: mediaTierInfo,
            thumbnailMediaTierInfo: thumbnailMediaTierInfo,
            tx: tx,
        )

        if let pendingAttachmentOrphanRecordId {
            // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
            orphanedAttachmentCleaner.releasePendingAttachment(
                withId: pendingAttachmentOrphanRecordId,
                tx: tx,
            )
        }

        // Make sure to clear out any orphaning jobs for the newly assigned
        // mediaName, in case it collides with an attachment that was
        // deleted recently.
        orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
            withMediaName: pendingAttachmentStreamInfo.mediaName,
            tx: tx,
        )

        // Anything that _can_ be uploaded, _should_ be enqueued for upload
        // immediately. Let the queue decide if enqeuing is needing and when
        // and whether to actually upload, but let it know about every new
        // stream created.
        if let newAttachmentOwner {
            backupAttachmentUploadScheduler.enqueueIfNeededWithOwner(
                existingAttachment,
                owner: newAttachmentOwner,
                tx: tx,
            )
        } else {
            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                existingAttachment,
                tx: tx,
            )
        }
        return existingAttachmentId
    }

    // MARK: Quoted Replies

    private func _createQuotedReplyMessageThumbnail(
        dataSource: QuotedReplyAttachmentDataSource,
        referenceOwner: AttachmentReference.OwnerBuilder,
        tx: DBWriteTransaction,
    ) throws {
        switch dataSource {
        case .pendingAttachment(let pendingAttachmentSource):
            try createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: .pendingAttachment(pendingAttachmentSource.pendingAttachment),
                    owner: referenceOwner,
                ),
                tx: tx,
            )
        case .originalAttachment(let originalAttachmentSource):
            guard let originalAttachment = attachmentStore.fetch(id: originalAttachmentSource.id, tx: tx) else {
                // The original has been deleted.
                throw OWSAssertionError("Original attachment not found")
            }

            let thumbnailMimeType: String
            let thumbnailBlurHash: String?
            let thumbnailTransitTierInfo: Attachment.TransitTierInfo?
            let thumbnailEncryptionKey: Data
            if
                originalAttachment.asStream() == nil,
                let thumbnailProtoFromSender = originalAttachmentSource.thumbnailPointerFromSender,
                let mimeType = thumbnailProtoFromSender.contentType,
                let transitTierInfo = try? self.transitTierInfo(from: thumbnailProtoFromSender)
            {
                // If the original is undownloaded, prefer to use the thumbnail
                // pointer from the sender.
                thumbnailMimeType = mimeType
                thumbnailBlurHash = thumbnailProtoFromSender.blurHash
                thumbnailTransitTierInfo = transitTierInfo
                thumbnailEncryptionKey = transitTierInfo.encryptionKey
            } else {
                // Otherwise fall back to the original's info, leaving transit tier
                // info blank (thumbnail cannot itself be downloaded) in the hopes
                // that we will download the original later and fill the thumbnail in.
                thumbnailMimeType = MimeTypeUtil.thumbnailMimetype(
                    fullsizeMimeType: originalAttachment.mimeType,
                    quality: .small,
                )
                thumbnailBlurHash = originalAttachment.blurHash
                thumbnailTransitTierInfo = nil
                thumbnailEncryptionKey = originalAttachment.encryptionKey
            }

            // Create a new attachment, but add foreign key reference to the original
            // so that when/if we download the original we can update this thumbnail'ed copy.
            let attachmentParams = Attachment.ConstructionParams.forQuotedReplyThumbnailPointer(
                originalAttachment: originalAttachment,
                thumbnailBlurHash: thumbnailBlurHash,
                thumbnailMimeType: thumbnailMimeType,
                thumbnailEncryptionKey: thumbnailEncryptionKey,
                thumbnailTransitTierInfo: thumbnailTransitTierInfo,
            )
            let referenceParams = AttachmentReference.ConstructionParams(
                owner: try referenceOwner.build(
                    knownIdInOwner: .none,
                    renderingFlag: originalAttachmentSource.renderingFlag,
                    contentType: nil,
                ),
                sourceFilename: originalAttachmentSource.sourceFilename,
                sourceUnencryptedByteCount: originalAttachmentSource.sourceUnencryptedByteCount,
                sourceMediaSizePixels: originalAttachmentSource.sourceMediaSizePixels,
            )

            try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx,
            )

            if let mediaName = attachmentParams.mediaName {
                orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                    withMediaName: mediaName,
                    tx: tx,
                )
            }

            // If we know we have a stream, enqueue the download at high priority
            // so that copy happens ASAP.
            if originalAttachment.asStream() != nil {
                guard
                    let newAttachmentReference = attachmentStore.fetchAnyReference(
                        owner: referenceParams.owner.id,
                        tx: tx,
                    )
                else {
                    throw OWSAssertionError("Missing attachment we just created")
                }
                attachmentDownloadManager.enqueueDownloadOfAttachment(
                    id: newAttachmentReference.attachmentRowId,
                    priority: .localClone,
                    source: .transitTier,
                    tx: tx,
                )
            }
        case .notFoundLocallyAttachment(let notFoundLocallyAttachmentSource):
            try createAttachmentPointer(
                from: OwnedAttachmentPointerProto(
                    proto: notFoundLocallyAttachmentSource.thumbnailPointerProto,
                    owner: referenceOwner,
                ),
                tx: tx,
            )
        }
    }
}

extension AttachmentManagerImpl {
    public enum Shims {
        public typealias StickerManager = _AttachmentManagerImpl_StickerManagerShim
    }

    public enum Wrappers {
        public typealias StickerManager = _AttachmentManagerImpl_StickerManagerWrapper
    }
}

public protocol _AttachmentManagerImpl_StickerManagerShim {
    func fetchInstalledSticker(packId: Data, stickerId: UInt32, tx: DBReadTransaction) -> InstalledSticker?
}

public class _AttachmentManagerImpl_StickerManagerWrapper: _AttachmentManagerImpl_StickerManagerShim {
    public init() {}

    public func fetchInstalledSticker(packId: Data, stickerId: UInt32, tx: DBReadTransaction) -> InstalledSticker? {
        return StickerManager.fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: tx)
    }
}
