//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct LinkPreviewDataSource {
    public let metadata: OWSLinkPreview.Metadata
    public let imageDataSource: AttachmentDataSource?
    public let isForwarded: Bool
}

public struct ValidatedLinkPreviewProto {
    public let preview: OWSLinkPreview
    public let imageProto: SSKProtoAttachmentPointer?
}

public struct ValidatedLinkPreviewDataSource {
    public let preview: OWSLinkPreview
    public let imageDataSource: AttachmentDataSource?
}

// MARK: -

public protocol LinkPreviewManager {
    func validateAndBuildLinkPreview(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
    ) throws -> ValidatedLinkPreviewProto

    func validateAndBuildStoryLinkPreview(
        from proto: SSKProtoPreview,
    ) throws -> ValidatedLinkPreviewProto

    func buildDataSource(
        from draft: OWSLinkPreviewDraft,
    ) async throws -> LinkPreviewDataSource

    func validateDataSource(
        dataSource: LinkPreviewDataSource,
        tx: DBWriteTransaction,
    ) throws -> ValidatedLinkPreviewDataSource

    func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoPreview

    func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentStoryMessage: StoryMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoPreview
}

// MARK: -

class LinkPreviewManagerImpl: LinkPreviewManager {
    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let db: any DB
    private let linkPreviewSettingStore: LinkPreviewSettingStore

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        db: any DB,
        linkPreviewSettingStore: LinkPreviewSettingStore,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.db = db
        self.linkPreviewSettingStore = linkPreviewSettingStore
    }

    // MARK: - Public

    func validateAndBuildLinkPreview(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
    ) throws -> ValidatedLinkPreviewProto {
        if dataMessage.attachments.count == 1, dataMessage.attachments[0].contentType != MimeType.textXSignalPlain.rawValue {
            Logger.error("Discarding link preview; message has non-text attachment.")
            throw LinkPreviewError.invalidPreview
        }
        if dataMessage.attachments.count > 1 {
            Logger.error("Discarding link preview; message has attachments.")
            throw LinkPreviewError.invalidPreview
        }
        guard let messageBody = dataMessage.body, messageBody.contains(proto.url) else {
            Logger.error("Url not present in body")
            throw LinkPreviewError.invalidPreview
        }
        guard
            LinkValidator.canParseURLs(in: messageBody),
            LinkValidator.isValidLink(linkText: proto.url)
        else {
            Logger.error("Discarding link preview; can't parse URLs in message.")
            throw LinkPreviewError.invalidPreview
        }

        return try buildValidatedLinkPreview(proto: proto)
    }

    func validateAndBuildStoryLinkPreview(
        from proto: SSKProtoPreview,
    ) throws -> ValidatedLinkPreviewProto {
        guard LinkValidator.isValidLink(linkText: proto.url) else {
            Logger.error("Discarding link preview; can't parse URLs in story message.")
            throw LinkPreviewError.invalidPreview
        }
        return try buildValidatedLinkPreview(proto: proto)
    }

    func buildDataSource(
        from draft: OWSLinkPreviewDraft,
    ) async throws -> LinkPreviewDataSource {
        let areLinkPreviewsEnabled = db.read { linkPreviewSettingStore.areLinkPreviewsEnabled(tx: $0) }
        guard draft.isForwarded || areLinkPreviewsEnabled else {
            throw LinkPreviewError.featureDisabled
        }

        let metadata = OWSLinkPreview.Metadata(
            urlString: draft.urlString,
            title: draft.title,
            previewDescription: draft.previewDescription,
            date: draft.date,
        )

        if
            let imageData = draft.imageData,
            let imageMimeType = draft.imageMimeType
        {
            let pendingAttachment = try await attachmentValidator.validateDataContents(
                imageData,
                mimeType: imageMimeType,
                renderingFlag: .default,
                sourceFilename: nil,
            )

            return LinkPreviewDataSource(
                metadata: metadata,
                imageDataSource: .pendingAttachment(pendingAttachment),
                isForwarded: draft.isForwarded,
            )
        } else {
            return LinkPreviewDataSource(
                metadata: metadata,
                imageDataSource: nil,
                isForwarded: draft.isForwarded,
            )
        }
    }

    func validateDataSource(
        dataSource: LinkPreviewDataSource,
        tx: DBWriteTransaction,
    ) throws -> ValidatedLinkPreviewDataSource {
        guard dataSource.isForwarded || linkPreviewSettingStore.areLinkPreviewsEnabled(tx: tx) else {
            throw LinkPreviewError.featureDisabled
        }
        return ValidatedLinkPreviewDataSource(
            preview: OWSLinkPreview(metadata: dataSource.metadata),
            imageDataSource: dataSource.imageDataSource,
        )
    }

    func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoPreview {
        let attachmentRef = parentMessage.sqliteRowId.map { rowId in
            return attachmentStore.fetchAnyReference(
                owner: .messageLinkPreview(messageRowId: rowId),
                tx: tx,
            )
        } ?? nil
        return try buildProtoForSending(
            linkPreview,
            previewAttachmentRef: attachmentRef,
            tx: tx,
        )
    }

    func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentStoryMessage: StoryMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoPreview {
        let attachmentRef = parentStoryMessage.id.map { rowId in
            return attachmentStore.fetchAnyReference(
                owner: .storyMessageLinkPreview(storyMessageRowId: rowId),
                tx: tx,
            )
        } ?? nil
        return try buildProtoForSending(
            linkPreview,
            previewAttachmentRef: attachmentRef,
            tx: tx,
        )
    }

    private func buildValidatedLinkPreview(
        proto: SSKProtoPreview,
    ) throws -> ValidatedLinkPreviewProto {
        let urlString = proto.url

        guard let url = URL(string: urlString), LinkPreviewHelper.isPermittedLinkPreviewUrl(url) else {
            Logger.error("Could not parse preview url.")
            throw LinkPreviewError.invalidPreview
        }

        var title: String?
        var previewDescription: String?
        if let rawTitle = proto.title {
            let normalizedTitle = LinkPreviewHelper.normalizeString(rawTitle, maxLines: 2)
            if !normalizedTitle.isEmpty {
                title = normalizedTitle
            }
        }
        if let rawDescription = proto.previewDescription, proto.title != proto.previewDescription {
            let normalizedDescription = LinkPreviewHelper.normalizeString(rawDescription, maxLines: 3)
            if !normalizedDescription.isEmpty {
                previewDescription = normalizedDescription
            }
        }

        // Zero check required. Some devices in the wild will explicitly set zero to mean "no date"
        let date: Date?
        if proto.hasDate, proto.date > 0 {
            date = Date(millisecondsSince1970: proto.date)
        } else {
            date = nil
        }

        return ValidatedLinkPreviewProto(
            preview: OWSLinkPreview(metadata: OWSLinkPreview.Metadata(
                urlString: urlString,
                title: title,
                previewDescription: previewDescription,
                date: date,
            )),
            imageProto: proto.image,
        )
    }

    // MARK: - Private, generating outgoing proto

    private func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        previewAttachmentRef: AttachmentReference?,
        tx: DBReadTransaction,
    ) throws -> SSKProtoPreview {
        guard let urlString = linkPreview.urlString else {
            Logger.error("Preview does not have url.")
            throw LinkPreviewError.invalidPreview
        }

        let builder = SSKProtoPreview.builder(url: urlString)

        if let title = linkPreview.title {
            builder.setTitle(title)
        }

        if let previewDescription = linkPreview.previewDescription {
            builder.setPreviewDescription(previewDescription)
        }

        if
            let previewAttachmentRef,
            let attachment = attachmentStore.fetch(id: previewAttachmentRef.attachmentRowId, tx: tx),
            let pointer = attachment.asTransitTierPointer(),
            case let .digestSHA256Ciphertext(digestSHA256Ciphertext) = pointer.info.integrityCheck
        {
            let attachmentProto = attachmentManager.buildProtoForSending(
                from: previewAttachmentRef,
                pointer: pointer,
                digestSHA256Ciphertext: digestSHA256Ciphertext,
            )
            builder.setImage(attachmentProto)
        }

        if let date = linkPreview.date, date.timeIntervalSince1970 > 0 {
            builder.setDate(date.ows_millisecondsSince1970)
        }

        return try builder.build()
    }
}
