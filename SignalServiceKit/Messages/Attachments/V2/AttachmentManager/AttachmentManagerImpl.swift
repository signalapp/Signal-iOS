//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class AttachmentManagerImpl: AttachmentManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let dateProvider: DateProvider
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    private let orphanedAttachmentStore: OrphanedAttachmentStore
    private let orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager
    private let remoteConfigManager: RemoteConfigManager
    private let stickerManager: Shims.StickerManager

    public init(
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentStore: AttachmentStore,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        dateProvider: @escaping DateProvider,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        remoteConfigManager: RemoteConfigManager,
        stickerManager: Shims.StickerManager
    ) {
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
        self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
        self.dateProvider = dateProvider
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.orphanedAttachmentStore = orphanedAttachmentStore
        self.orphanedBackupAttachmentManager = orphanedBackupAttachmentManager
        self.remoteConfigManager = remoteConfigManager
        self.stickerManager = stickerManager
    }

    // MARK: - Public

    // MARK: Creating Attachments from source

    public func createAttachmentPointers(
        from protos: [OwnedAttachmentPointerProto],
        tx: DBWriteTransaction
    ) throws {
        guard protos.count < UInt32.max else {
            throw OWSAssertionError("Input array too large")
        }
        try createAttachments(
            protos,
            mimeType: \.proto.contentType,
            owner: \.owner,
            output: \.proto,
            createFn: {
                try self._createAttachmentPointer(
                    from: $0,
                    owner: $1,
                    sourceOrder: $2,
                    tx: $3
                )
            },
            tx: tx
        )
    }

    public func createAttachmentPointers(
        from backupProtos: [OwnedAttachmentBackupPointerProto],
        uploadEra: String,
        tx: DBWriteTransaction
    ) -> [OwnedAttachmentBackupPointerProto.CreationError] {
        let results = createAttachments(
            backupProtos,
            mimeType: { $0.proto.contentType },
            owner: \.owner,
            output: { $0 },
            createFn: {
                 return self._createAttachmentPointer(
                    from: $0,
                    owner: $1,
                    sourceOrder: $2,
                    uploadEra: uploadEra,
                    tx: $3
                )
            },
            tx: tx
        )
        return results.compactMap { result in
            switch result {
            case .success:
                return nil
            case .failure(let error):
                return error
            }
        }
    }

    public func createAttachmentStreams(
        consuming dataSources: [OwnedAttachmentDataSource],
        tx: DBWriteTransaction
    ) throws {
        guard dataSources.count < UInt32.max else {
            throw OWSAssertionError("Input array too large")
        }
        try createAttachments(
            dataSources,
            mimeType: { $0.mimeType },
            owner: \.owner,
            output: \.source,
            createFn: {
                try self._createAttachmentStream(
                    consuming: $0,
                    owner: $1,
                    sourceOrder: $2,
                    tx: $3
                )
            },
            tx: tx
        )
        // When we create the attachment streams we schedule a backup of the
        // new attachments. Kick the tires so that upload starts happening now.
        backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
    }

    // MARK: Quoted Replies

    public func quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> QuotedAttachmentInfo? {
        guard let originalMessageRowId = originalMessage.sqliteRowId else {
            owsFailDebug("Cloning attachment for un-inserted message")
            return nil
        }
        return _quotedReplyAttachmentInfo(originalMessageRowId: originalMessageRowId, tx: tx).0?.info
    }

    public func createQuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyAttachmentDataSource,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo> {
        let (info, isStub) = self._quotedReplyAttachmentInfo(
            originalAttachmentMimeType: dataSource.originalAttachmentMimeType,
            originalReferenceSourceFilename: dataSource.originalAttachmentSourceFilename,
            originalReferenceRenderingFlag: dataSource.renderingFlag
        )
        if isStub {
            return .withoutFinalizer(info)
        }
        return OwnedAttachmentBuilder<QuotedAttachmentInfo>(
            info: info,
            finalize: { [self, dataSource] ownerId, tx in
                let replyMessageOwner: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder
                switch ownerId {
                case .quotedReplyAttachment(let metadata):
                    replyMessageOwner = metadata
                default:
                    owsFailDebug("Invalid owner sent to quoted reply builder!")
                    return
                }

                try self.createQuotedReplyMessageThumbnail(
                    consuming: .init(
                        dataSource: dataSource,
                        owner: replyMessageOwner
                    ),
                    tx: tx
                )
            }
        )
    }

    private func createQuotedReplyMessageThumbnail(
        consuming dataSource: OwnedQuotedReplyAttachmentDataSource,
        tx: DBWriteTransaction
    ) throws {
        switch dataSource.source.source {
        case .originalAttachment:
            // If the goal is to capture the original message's attachment,
            // ensure we can actually capture its info.
            if let originalMessageRowId = dataSource.source.originalMessageRowId {
                let (info, isStub) = _quotedReplyAttachmentInfo(originalMessageRowId: originalMessageRowId, tx: tx)
                guard
                    info != nil,
                    !isStub
                else {
                    return
                }
            }
        case .pendingAttachment, .quotedAttachmentProto:
            break
        }
        try _createQuotedReplyMessageThumbnail(
            dataSource: dataSource,
            tx: tx
        )
    }

    // MARK: Removing Attachments

    public func removeAttachment(
        reference: AttachmentReference,
        tx: DBWriteTransaction
    ) throws {
        try attachmentStore.removeOwner(
            reference: reference,
            tx: tx
        )
    }

    public func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    ) throws {
        try attachmentStore.fetchReferences(owners: owners, tx: tx)
            .forEach { reference in
                try attachmentStore.removeAllOwners(
                    withId: reference.owner.id,
                    for: reference.attachmentRowId,
                    tx: tx
                )
            }
    }

    // MARK: - Helpers

    private typealias OwnerId = AttachmentReference.OwnerId
    private typealias OwnerBuilder = AttachmentReference.OwnerBuilder

    // MARK: Creating Attachments from source

    @discardableResult
    private func createAttachments<Input, Output, Result>(
        _ inputArray: [Input],
        mimeType: (Input) -> String?,
        owner: (Input) -> OwnerBuilder,
        output: (Input) -> Output,
        createFn: (Output, OwnerBuilder, UInt32?, DBWriteTransaction) throws -> Result,
        tx: DBWriteTransaction
    ) rethrows -> [Result] {
        var results = [Result]()
        var indexOffset: Int = 0
        for (i, input) in inputArray.enumerated() {
            let sourceOrder: UInt32?
            var ownerForInput = owner(input)
            switch ownerForInput {
            case .messageBodyAttachment(let metadata):
                // Convert text mime type attachments in the first spot to oversize text.
                if mimeType(input) == MimeType.textXSignalPlain.rawValue {
                    ownerForInput = .messageOversizeText(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        isPastEditRevision: metadata.isPastEditRevision
                    ))
                    indexOffset = -1
                    sourceOrder = nil
                } else {
                    sourceOrder = UInt32(i + indexOffset)
                }
            default:
                sourceOrder = nil
                if inputArray.count > 1 {
                    // Only allow multiple attachments in the case of message body attachments.
                    owsFailDebug("Can't have multiple attachments under the same owner reference!")
                }
            }

            let result = try createFn(output(input), ownerForInput, sourceOrder, tx)
            results.append(result)
        }
        return results
    }

    private func _createAttachmentPointer(
        from proto: SSKProtoAttachmentPointer,
        owner: OwnerBuilder,
        // Nil if no order is to be applied.
        sourceOrder: UInt32?,
        tx: DBWriteTransaction
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
            sourceFilename: sourceFilename
        )

        let attachmentParams = Attachment.ConstructionParams.fromPointer(
            blurHash: proto.blurHash,
            mimeType: mimeType,
            encryptionKey: transitTierInfo.encryptionKey,
            transitTierInfo: transitTierInfo
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
                orderInOwner: sourceOrder,
                knownIdInOwner: knownIdFromProto,
                renderingFlag: .fromProto(proto),
                // Not downloaded so we don't know the content type.
                contentType: nil,
                // This should be unset for newly-incoming attachments, but it's
                // still technically in the proto definition.
                caption: proto.hasCaption ? proto.caption : nil
            ),
            sourceFilename: sourceFilename,
            sourceUnencryptedByteCount: proto.size,
            sourceMediaSizePixels: sourceMediaSizePixels
        )

        try attachmentStore.insert(
            attachmentParams,
            reference: referenceParams,
            tx: tx
        )

        if let mediaName = attachmentParams.mediaName {
            orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                withMediaName: mediaName,
                tx: tx
            )
        }

        switch referenceParams.owner {
        case .message(.sticker(let stickerInfo)):
            // Only for stickers, schedule a high priority "download"
            // from the local sticker pack if we have it.
            let installedSticker = self.stickerManager.fetchInstalledSticker(
                packId: stickerInfo.stickerPackId,
                stickerId: stickerInfo.stickerId,
                tx: tx
            )
            if installedSticker != nil {
                guard let newAttachmentReference = attachmentStore.fetchFirstReference(
                    owner: referenceParams.owner.id,
                    tx: tx
                ) else {
                    throw OWSAssertionError("Missing attachment we just created")
                }
                attachmentDownloadManager.enqueueDownloadOfAttachment(
                    id: newAttachmentReference.attachmentRowId,
                    priority: .localClone,
                    source: .transitTier,
                    tx: tx
                )
            }
        default:
            break
        }
    }

    private func transitTierInfo(
        from proto: SSKProtoAttachmentPointer
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
            lastDownloadAttemptTimestamp: nil
        )
    }

    private func _createAttachmentPointer(
        from ownedProto: OwnedAttachmentBackupPointerProto,
        owner: OwnerBuilder,
        // Nil if no order is to be applied.
        sourceOrder: UInt32?,
        uploadEra: String,
        tx: DBWriteTransaction
    ) -> Result<Void, OwnedAttachmentBackupPointerProto.CreationError> {
        let proto = ownedProto.proto

        let knownIdFromProto = ownedProto.clientUUID.map {
            return OwnerBuilder.KnownIdInOwner.known($0)
        } ?? .knownNil

        let sourceFilename = proto.fileName.nilIfEmpty
        let mimeType = self.mimeType(
            fromProtoContentType: proto.contentType,
            sourceFilename: sourceFilename
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
            incrementalMacInfo = Attachment.IncrementalMacInfo(
                mac: proto.incrementalMac,
                chunkSize: proto.incrementalMacChunkSize
            )
        } else {
            incrementalMacInfo = nil
        }

        let attachmentParams: Attachment.ConstructionParams
        let sourceUnencryptedByteCount: UInt32?

        // Prefer the newer locatorInfo format, but for backwards compatibility
        // fall back to the oneOfLocator if unset.
        if proto.hasLocatorInfo {

            if let encryptionKey = proto.locatorInfo.key.nilIfEmpty {
                let transitTierInfo: Attachment.TransitTierInfo?
                switch self.transitTierInfo(
                    from: proto.locatorInfo,
                    owningMessageReceivedAtTimestamp: ownedProto.owningMessageReceivedAtTimestamp,
                    incrementalMacInfo: incrementalMacInfo
                ) {
                case .success(let value):
                    transitTierInfo = value
                case .failure(let error):
                    return .failure(error)
                }

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
                        transitTierInfo: transitTierInfo,
                        sha256ContentHash: sha256ContentHash,
                        mediaName: Attachment.mediaName(
                            sha256ContentHash: sha256ContentHash,
                            encryptionKey: encryptionKey
                        ),
                        mediaTierInfo: .init(
                            cdnNumber: mediaTierCdnNumber,
                            unencryptedByteCount: proto.locatorInfo.size,
                            sha256ContentHash: sha256ContentHash,
                            incrementalMacInfo: incrementalMacInfo,
                            uploadEra: uploadEra,
                            lastDownloadAttemptTimestamp: nil
                        ),
                        thumbnailMediaTierInfo: .init(
                            // Assume the thumbnail uses the same cdn as fullsize;
                            // this _can_ go wrong if the server changes cdns between
                            // the two uploads but worst case we lose the thumbnail.
                            cdnNumber: mediaTierCdnNumber,
                            uploadEra: uploadEra,
                            lastDownloadAttemptTimestamp: nil
                        )
                    )
                case .encryptedDigest, .none:
                    if let transitTierInfo {
                        attachmentParams = .fromBackup(
                            blurHash: proto.blurHash.nilIfEmpty,
                            mimeType: mimeType,
                            encryptionKey: encryptionKey,
                            transitTierInfo: transitTierInfo,
                            sha256ContentHash: nil,
                            mediaName: nil,
                            mediaTierInfo: nil,
                            thumbnailMediaTierInfo: nil
                        )
                    } else {
                        attachmentParams = .forInvalidBackupAttachment(
                            blurHash: proto.blurHash.nilIfEmpty,
                            mimeType: mimeType
                        )
                    }
                }
            } else {
                attachmentParams = .forInvalidBackupAttachment(
                    blurHash: proto.blurHash.nilIfEmpty,
                    mimeType: mimeType
                )
                sourceUnencryptedByteCount = nil
            }
        } else {
            switch proto.locator {
            case .backupLocator(let backupLocator):
                guard let encryptionKey = backupLocator.key.nilIfEmpty else {
                    return .failure(.missingEncryptionKey)
                }

                // We no longer support importing backup media tier info from legacy locators.
                // This is fine because any client will backups enabled that might actually have
                // something on media tier will also be using the new LocatorInfo.
                let transitTierInfo: Attachment.TransitTierInfo?
                switch self.transitTierInfo(from: backupLocator, incrementalMacInfo: incrementalMacInfo) {
                case .success(let value):
                    transitTierInfo = value
                case .failure(let error):
                    return .failure(error)
                }

                if let transitTierInfo {
                    attachmentParams = .fromPointer(
                        blurHash: proto.blurHash.nilIfEmpty,
                        mimeType: mimeType,
                        encryptionKey: encryptionKey,
                        transitTierInfo: transitTierInfo
                    )
                    sourceUnencryptedByteCount = transitTierInfo.unencryptedByteCount
                } else {
                    attachmentParams = .forInvalidBackupAttachment(
                        blurHash: proto.blurHash.nilIfEmpty,
                        mimeType: mimeType
                    )
                    sourceUnencryptedByteCount = nil
                }
            case .attachmentLocator(let attachmentLocator):
                let transitTierInfo: Attachment.TransitTierInfo?
                switch self.transitTierInfo(
                    from: attachmentLocator,
                    owningMessageReceivedAtTimestamp: ownedProto.owningMessageReceivedAtTimestamp,
                    incrementalMacInfo: incrementalMacInfo
                ) {
                case .success(let value):
                    transitTierInfo = value
                case .failure(let error):
                    return .failure(error)
                }

                if let transitTierInfo {
                    attachmentParams = .fromPointer(
                        blurHash: proto.blurHash.nilIfEmpty,
                        mimeType: mimeType,
                        encryptionKey: attachmentLocator.key,
                        transitTierInfo: transitTierInfo
                    )
                    sourceUnencryptedByteCount = transitTierInfo.unencryptedByteCount
                } else {
                    // We successfully parsed the transit tier info, but decided we
                    // should discard it. To that end, fall through to the handling
                    // for invalid attachment locators.
                    fallthrough
                }
            case .invalidAttachmentLocator, .none:
                attachmentParams = .forInvalidBackupAttachment(
                    blurHash: proto.blurHash.nilIfEmpty,
                    mimeType: mimeType
                )
                sourceUnencryptedByteCount = nil
            }
        }

        let referenceParams: AttachmentReference.ConstructionParams
        do {
            referenceParams = AttachmentReference.ConstructionParams(
                owner: try owner.build(
                    orderInOwner: sourceOrder,
                    knownIdInOwner: knownIdFromProto,
                    renderingFlag: ownedProto.renderingFlag,
                    // Not downloaded so we don't know the content type.
                    contentType: nil,
                    // Restored legacy attachments might have a caption.
                    caption: proto.hasCaption ? proto.caption : nil
                ),
                sourceFilename: sourceFilename,
                sourceUnencryptedByteCount: sourceUnencryptedByteCount,
                sourceMediaSizePixels: sourceMediaSizePixels
            )
        } catch {
            return .failure(.dbInsertionError(error))
        }

        do {
            try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx
            )

            if let mediaName = attachmentParams.mediaName {
                orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                    withMediaName: mediaName,
                    tx: tx
                )
            }

            return .success(())
        } catch let AttachmentInsertError.duplicateMediaName(existingAttachmentId) {
            // We already have an attachment with the same mediaName (likely from this same
            // backup). Just point the reference at the existing attachment.
            do {
                try attachmentStore.addOwner(
                    referenceParams,
                    for: existingAttachmentId,
                    tx: tx
                )
                return .success(())
            } catch {
                return .failure(.dbInsertionError(error))
            }
        } catch {
            return .failure(.dbInsertionError(error))
        }
    }

    private func transitTierInfo(
        from backupLocator: BackupProto_FilePointer.BackupLocator,
        incrementalMacInfo: Attachment.IncrementalMacInfo?
    ) -> Result<Attachment.TransitTierInfo?, OwnedAttachmentBackupPointerProto.CreationError> {
        guard backupLocator.key.count > 0 else { return .failure(.missingEncryptionKey) }
        guard backupLocator.digest.count > 0 else { return .failure(.missingDigest) }

        guard backupLocator.hasTransitCdnNumber, backupLocator.hasTransitCdnKey else {
            // Ok to be missing transit-tier CDN info on a backup locator, if
            // this attachment was never uploaded.
            return .success(nil)
        }

        let unencryptedByteCount: UInt32?
        if backupLocator.size > 0 {
            unencryptedByteCount = backupLocator.size
        } else {
            unencryptedByteCount = nil
        }

        return .success(Attachment.TransitTierInfo(
            cdnNumber: backupLocator.transitCdnNumber,
            cdnKey: backupLocator.transitCdnKey,
            // Treat it as uploaded now.
            uploadTimestamp: Date().ows_millisecondsSince1970,
            encryptionKey: backupLocator.key,
            unencryptedByteCount: unencryptedByteCount,
            integrityCheck: .digestSHA256Ciphertext(backupLocator.digest),
            incrementalMacInfo: incrementalMacInfo,
            lastDownloadAttemptTimestamp: nil
        ))
    }

    private func transitTierInfo(
        from attachmentLocator: BackupProto_FilePointer.AttachmentLocator,
        owningMessageReceivedAtTimestamp: UInt64?,
        incrementalMacInfo: Attachment.IncrementalMacInfo?
    ) -> Result<Attachment.TransitTierInfo?, OwnedAttachmentBackupPointerProto.CreationError> {
        guard attachmentLocator.digest.count > 0 else { return .failure(.missingDigest) }
        guard attachmentLocator.cdnKey.count > 0 else { return .failure(.missingTransitCdnKey) }

        let uploadTimestampMs: UInt64
        if attachmentLocator.hasUploadTimestamp, attachmentLocator.uploadTimestamp > 0 {
            uploadTimestampMs = attachmentLocator.uploadTimestamp
        } else if let owningMessageReceivedAtTimestamp {
            // iOS historically did not set the `uploadTimestamp` on attachment
            // protos we sent with outgoing messages. As a workaround for our
            // purposes here, we'll sub in the `receivedAt` timestamp for the
            // message this attachment is owned by (if applicable).
            uploadTimestampMs = owningMessageReceivedAtTimestamp
        } else {
            uploadTimestampMs = 0
        }

        let maxTransitTierAge: TimeInterval = Double(remoteConfigManager.currentConfig().messageQueueTimeMs) / 1000
        let now = dateProvider()
        guard
            Date(millisecondsSince1970: uploadTimestampMs)
                .addingTimeInterval(maxTransitTierAge) > now
        else {
            // This suggests that the attachment has expired off the transit
            // tier, so we can proactively drop the transit tier info. That'll
            // let us show users immediately that the attachment isn't available
            // (on the transit tier), and avoid a doomed-to-fail network request
            // that we'd otherwise make to confirm that it's gone.
            return .success(nil)
        }

        let unencryptedByteCount: UInt32?
        if attachmentLocator.size > 0 {
            unencryptedByteCount = attachmentLocator.size
        } else {
            unencryptedByteCount = nil
        }

        return .success(Attachment.TransitTierInfo(
            cdnNumber: attachmentLocator.cdnNumber,
            cdnKey: attachmentLocator.cdnKey,
            // Note that this can be unset, which presents as 0,
            // so we'll treat this as having uploaded in the distant
            // past, which is fine and matches desired behavior.
            uploadTimestamp: attachmentLocator.uploadTimestamp,
            encryptionKey: attachmentLocator.key,
            unencryptedByteCount: unencryptedByteCount,
            integrityCheck: .digestSHA256Ciphertext(attachmentLocator.digest),
            incrementalMacInfo: incrementalMacInfo,
            lastDownloadAttemptTimestamp: nil
        ))
    }

    private func transitTierInfo(
        from locatorInfo: BackupProto_FilePointer.LocatorInfo,
        owningMessageReceivedAtTimestamp: UInt64?,
        incrementalMacInfo: Attachment.IncrementalMacInfo?
    ) -> Result<Attachment.TransitTierInfo?, OwnedAttachmentBackupPointerProto.CreationError> {
        guard locatorInfo.key.count > 0 else { return .failure(.missingEncryptionKey) }

        guard locatorInfo.transitCdnKey.isEmpty.negated else {
            // Ok to be missing transit-tier CDN info on a backup locator, if
            // this attachment was never uploaded.
            return .success(nil)
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
                return .success(nil)
            }
            integrityCheck = .sha256ContentHash(data)
        case .encryptedDigest(let data):
            guard !data.isEmpty else {
                return .success(nil)
            }
            integrityCheck = .digestSHA256Ciphertext(data)
        case .none:
            if let legacyDigest = locatorInfo.legacyDigest.nilIfEmpty {
                integrityCheck = .digestSHA256Ciphertext(legacyDigest)
            } else {
                return .success(nil)
            }
        }

        return .success(Attachment.TransitTierInfo(
            cdnNumber: locatorInfo.transitCdnNumber,
            cdnKey: locatorInfo.transitCdnKey,
            uploadTimestamp: uploadTimestampMs,
            encryptionKey: locatorInfo.key,
            unencryptedByteCount: unencryptedByteCount,
            integrityCheck: integrityCheck,
            incrementalMacInfo: incrementalMacInfo,
            lastDownloadAttemptTimestamp: nil
        ))
    }

    private func mimeType(
        fromProtoContentType contentType: String?,
        sourceFilename: String?
    ) -> String {
        if let protoMimeType = contentType?.nilIfEmpty {
            return protoMimeType
        } else {
            // Content type might not set if the sending client can't
            // infer a MIME type from the file extension.
            if
                let sourceFilename,
                let fileExtension = sourceFilename.fileExtension?.lowercased().nilIfEmpty,
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
        consuming dataSource: AttachmentDataSource,
        owner: OwnerBuilder,
        // Nil if no order is to be applied.
        sourceOrder: UInt32?,
        tx: DBWriteTransaction
    ) throws {
        switch dataSource {
        case .existingAttachment(let existingAttachmentMetadata):
            guard let existingAttachment = attachmentStore.fetch(id: existingAttachmentMetadata.id, tx: tx) else {
                throw OWSAssertionError("Missing existing attachment!")
            }

            let owner: AttachmentReference.Owner = try owner.build(
                orderInOwner: sourceOrder,
                knownIdInOwner: .none,
                renderingFlag: existingAttachmentMetadata.renderingFlag,
                contentType: existingAttachment.streamInfo?.contentType.raw
            )
            let referenceParams = AttachmentReference.ConstructionParams(
                owner: owner,
                sourceFilename: existingAttachmentMetadata.sourceFilename,
                sourceUnencryptedByteCount: existingAttachmentMetadata.sourceUnencryptedByteCount,
                sourceMediaSizePixels: existingAttachmentMetadata.sourceMediaSizePixels
            )
            try attachmentStore.addOwner(
                referenceParams,
                for: existingAttachment.id,
                tx: tx
            )
        case .pendingAttachment(let pendingAttachment):
            let owner: AttachmentReference.Owner = try owner.build(
                orderInOwner: sourceOrder,
                knownIdInOwner: .none,
                renderingFlag: pendingAttachment.renderingFlag,
                contentType: pendingAttachment.validatedContentType.raw
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
                sourceMediaSizePixels: mediaSizePixels
            )
            let mediaName = Attachment.mediaName(
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                encryptionKey: pendingAttachment.encryptionKey
            )
            let streamInfo = Attachment.StreamInfo(
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                mediaName: mediaName,
                encryptedByteCount: pendingAttachment.encryptedByteCount,
                unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                contentType: pendingAttachment.validatedContentType,
                digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                localRelativeFilePath: pendingAttachment.localRelativeFilePath
            )
            let attachmentParams = Attachment.ConstructionParams.fromStream(
                blurHash: pendingAttachment.blurHash,
                mimeType: pendingAttachment.mimeType,
                encryptionKey: pendingAttachment.encryptionKey,
                streamInfo: streamInfo,
                sha256ContentHash: pendingAttachment.sha256ContentHash,
                mediaName: mediaName
            )

            let hasOrphanRecord = orphanedAttachmentStore.orphanAttachmentExists(
                with: pendingAttachment.orphanRecordId,
                tx: tx
            )

            do {
                let hasExistingAttachmentWithSameFile = attachmentStore.fetchAttachment(
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    tx: tx
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
                    tx: tx
                )
                if hasOrphanRecord {
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)
                }
                if let mediaName = attachmentParams.mediaName {
                    orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                        withMediaName: mediaName,
                        tx: tx
                    )

                    if
                        let attachment = attachmentStore.fetchAttachment(
                            mediaName: mediaName,
                            tx: tx
                        )
                    {
                        try backupAttachmentUploadScheduler.enqueueIfNeededWithOwner(
                            attachment,
                            owner: owner,
                            tx: tx
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
                        pendingAttachmentTransitTierInfo: attachmentParams.transitTierInfo,
                        attachmentStore: attachmentStore,
                        orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                        orphanedAttachmentStore: orphanedAttachmentStore,
                        backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                        orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
                        tx: tx
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
                    tx: tx
                )
                return
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
    internal static func handleAttachmentInsertError(
        _ error: AttachmentInsertError,
        newAttachmentOwner: AttachmentReference.Owner? = nil,
        pendingAttachmentStreamInfo: Attachment.StreamInfo,
        pendingAttachmentEncryptionKey: Data,
        pendingAttachmentMimeType: String,
        pendingAttachmentOrphanRecordId: OrphanedAttachmentRecord.IDType?,
        pendingAttachmentTransitTierInfo: Attachment.TransitTierInfo?,
        attachmentStore: AttachmentStore,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        tx: DBWriteTransaction
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
            try orphanedBackupAttachmentManager.orphanExistingMediaTierUploads(
                of: existingAttachment,
                tx: tx
            )

            // Orphan the local thumbnail file, if the attachment had one, since
            // we now use a different encryption key and we don't keep thumbnails
            // when we have a stream, anyway.
            if let thumbnailRelativeFilePath = existingAttachment.localRelativeFilePathThumbnail {
                var thumbnailOrphanRecord = OrphanedAttachmentRecord(
                    localRelativeFilePath: nil,
                    localRelativeFilePathThumbnail: thumbnailRelativeFilePath,
                    localRelativeFilePathAudioWaveform: nil,
                    localRelativeFilePathVideoStillFrame: nil
                )
                try orphanedAttachmentStore.insert(&thumbnailOrphanRecord, tx: tx)
            }
        }

        // Transit tier info has its own key independent of the local file encryption key;
        // we should just keep whichever upload we think is newer.
        let transitTierInfo: Attachment.TransitTierInfo?
        if
            let existingTransitTierInfo = existingAttachment.transitTierInfo,
            let pendingAttachmentTransitTierInfo
        {
            if existingTransitTierInfo.uploadTimestamp > pendingAttachmentTransitTierInfo.uploadTimestamp {
                transitTierInfo = existingTransitTierInfo
            } else {
                transitTierInfo = pendingAttachmentTransitTierInfo
            }
        } else {
            // Take whichever one we've got.
            transitTierInfo = existingAttachment.transitTierInfo ?? pendingAttachmentTransitTierInfo
        }

        // Set the stream info on the existing attachment, if needed.
        try attachmentStore.merge(
            streamInfo: pendingAttachmentStreamInfo,
            into: existingAttachment,
            encryptionKey: pendingAttachmentEncryptionKey,
            validatedMimeType: pendingAttachmentMimeType,
            transitTierInfo: transitTierInfo,
            mediaTierInfo: mediaTierInfo,
            thumbnailMediaTierInfo: thumbnailMediaTierInfo,
            tx: tx
        )

        if let pendingAttachmentOrphanRecordId {
            // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
            orphanedAttachmentCleaner.releasePendingAttachment(
                withId: pendingAttachmentOrphanRecordId,
                tx: tx
            )
        }

        // Make sure to clear out any orphaning jobs for the newly assigned
        // mediaName, in case it collides with an attachment that was
        // deleted recently.
        orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
            withMediaName: pendingAttachmentStreamInfo.mediaName,
            tx: tx
        )

        // Anything that _can_ be uploaded, _should_ be enqueued for upload
        // immediately. Let the queue decide if enqeuing is needing and when
        // and whether to actually upload, but let it know about every new
        // stream created.
        if let newAttachmentOwner {
            try backupAttachmentUploadScheduler.enqueueIfNeededWithOwner(
                existingAttachment,
                owner: newAttachmentOwner,
                tx: tx
            )
        } else {
            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                existingAttachment,
                tx: tx
            )
        }
        return existingAttachmentId
    }

    // MARK: Quoted Replies

    private struct WrappedQuotedAttachmentInfo {
        let originalAttachmentReference: AttachmentReference
        let originalAttachment: Attachment
        let info: QuotedAttachmentInfo
    }

    private func _quotedReplyAttachmentInfo(
        originalMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> (WrappedQuotedAttachmentInfo?, isStub: Bool) {
        guard
            let originalReference = attachmentStore.attachmentToUseInQuote(
                originalMessageRowId: originalMessageRowId,
                tx: tx
            ),
            let originalAttachment = attachmentStore.fetch(id: originalReference.attachmentRowId, tx: tx)
        else {
            return (nil, true)
        }
        let (info, isStub) = self._quotedReplyAttachmentInfo(
            originalAttachmentMimeType: originalAttachment.mimeType,
            originalReferenceSourceFilename: originalReference.sourceFilename,
            originalReferenceRenderingFlag: originalReference.renderingFlag
        )
        return (
            .init(
                originalAttachmentReference: originalReference,
                originalAttachment: originalAttachment,
                info: info
            ),
            isStub
        )
    }

    private func _quotedReplyAttachmentInfo(
        originalAttachmentMimeType: String,
        originalReferenceSourceFilename: String?,
        originalReferenceRenderingFlag: AttachmentReference.RenderingFlag
    ) -> (QuotedAttachmentInfo, isStub: Bool) {
        let renderingFlag: AttachmentReference.RenderingFlag
        switch originalReferenceRenderingFlag {
        case .borderless:
            // Not allowed in quoted
            renderingFlag = .default
        default:
            renderingFlag = originalReferenceRenderingFlag
        }
        guard MimeTypeUtil.isSupportedVisualMediaMimeType(originalAttachmentMimeType) else {
            // Can't make a thumbnail, just return a stub.
            return (
                QuotedAttachmentInfo(
                    info: .stub(
                        withOriginalAttachmentMimeType: originalAttachmentMimeType,
                        originalAttachmentSourceFilename: originalReferenceSourceFilename
                    ),
                    renderingFlag: renderingFlag
                ),
                isStub: true
            )
        }

        return (
            QuotedAttachmentInfo(
                info: .forThumbnailReference(
                    withOriginalAttachmentMimeType: originalAttachmentMimeType,
                    originalAttachmentSourceFilename: originalReferenceSourceFilename
                ),
                renderingFlag: renderingFlag
            ),
            isStub: false
        )
    }

    private func _createQuotedReplyMessageThumbnail(
        dataSource: OwnedQuotedReplyAttachmentDataSource,
        tx: DBWriteTransaction
    ) throws {
        let referenceOwner = AttachmentReference.OwnerBuilder.quotedReplyAttachment(dataSource.owner)

        switch dataSource.source.source {
        case .quotedAttachmentProto(let quotedAttachmentProtoSource):
            try self._createAttachmentPointer(
                from: quotedAttachmentProtoSource.thumbnail,
                owner: referenceOwner,
                sourceOrder: nil,
                tx: tx
            )
        case .pendingAttachment(let pendingAttachmentSource):
            try self._createAttachmentStream(
                consuming: .pendingAttachment(pendingAttachmentSource.pendingAttachment),
                owner: referenceOwner,
                sourceOrder: nil,
                tx: tx
            )
            // When we create the attachment stream we schedule a backup of the
            // new attachment. Kick the tires so that upload starts happening now.
            backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
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
                    quality: .small
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
                thumbnailTransitTierInfo: thumbnailTransitTierInfo
            )
            let referenceParams = AttachmentReference.ConstructionParams(
                owner: try referenceOwner.build(
                    orderInOwner: nil,
                    knownIdInOwner: .none,
                    renderingFlag: originalAttachmentSource.renderingFlag,
                    contentType: nil
                ),
                sourceFilename: originalAttachmentSource.sourceFilename,
                sourceUnencryptedByteCount: originalAttachmentSource.sourceUnencryptedByteCount,
                sourceMediaSizePixels: originalAttachmentSource.sourceMediaSizePixels
            )

            try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx
            )

            if let mediaName = attachmentParams.mediaName {
                orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                    withMediaName: mediaName,
                    tx: tx
                )
            }

            // If we know we have a stream, enqueue the download at high priority
            // so that copy happens ASAP.
            if originalAttachment.asStream() != nil {
                guard let newAttachmentReference = attachmentStore.fetchFirstReference(
                    owner: referenceParams.owner.id,
                    tx: tx
                ) else {
                    throw OWSAssertionError("Missing attachment we just created")
                }
                attachmentDownloadManager.enqueueDownloadOfAttachment(
                    id: newAttachmentReference.attachmentRowId,
                    priority: .localClone,
                    source: .transitTier,
                    tx: tx
                )
            }
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
        return StickerManager.fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
