//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LinkPreviewManagerImpl: LinkPreviewManager {
    private let attachmentManager: TSResourceManager
    private let attachmentStore: TSResourceStore
    private let attachmentValidator: AttachmentContentValidator
    private let db: DB
    private let groupsV2: Shims.GroupsV2
    private let sskPreferences: Shims.SSKPreferences

    public init(
        attachmentManager: TSResourceManager,
        attachmentStore: TSResourceStore,
        attachmentValidator: AttachmentContentValidator,
        db: DB,
        groupsV2: Shims.GroupsV2,
        sskPreferences: Shims.SSKPreferences
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.db = db
        self.groupsV2 = groupsV2
        self.sskPreferences = sskPreferences
    }

    private lazy var defaultBuilder = LinkPreviewTSResourceBuilder(
        attachmentValidator: attachmentValidator,
        tsResourceManager: attachmentManager
    )

    // MARK: - Public

    public func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool {
        sskPreferences.areLinkPreviewsEnabled(tx: tx)
    }

    public func fetchLinkPreview(for url: URL) async throws -> OWSLinkPreviewDraft {
        let areLinkPreviewsEnabled: Bool = self.db.read(block: self.areLinkPreviewsEnabled(tx:))
        guard areLinkPreviewsEnabled else {
            throw LinkPreviewError.featureDisabled
        }

        let linkPreviewDraft: OWSLinkPreviewDraft
        if StickerPackInfo.isStickerPackShare(url) {
            linkPreviewDraft = try await self.linkPreviewDraft(forStickerShare: url)
        } else if GroupManager.isPossibleGroupInviteLink(url) {
            linkPreviewDraft = try await self.linkPreviewDraft(forGroupInviteLink: url)
        } else {
            linkPreviewDraft = try await self.fetchLinkPreview(forGenericUrl: url)
        }
        guard linkPreviewDraft.isValid() else {
            throw LinkPreviewError.noPreview
        }
        return linkPreviewDraft
    }

    public func validateAndBuildLinkPreview(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try validateAndBuildLinkPreview(
            from: proto,
            dataMessage: dataMessage,
            builder: defaultBuilder,
            ownerType: ownerType,
            tx: tx
        )
    }

    public func validateAndBuildLinkPreview<Builder: LinkPreviewBuilder>(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        builder: Builder,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
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

        return try buildValidatedLinkPreview(proto: proto, builder: defaultBuilder, ownerType: ownerType, tx: tx)
    }

    public func validateAndBuildStoryLinkPreview(
        from proto: SSKProtoPreview,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard LinkValidator.isValidLink(linkText: proto.url) else {
            Logger.error("Discarding link preview; can't parse URLs in story message.")
            throw LinkPreviewError.invalidPreview
        }
        return try buildValidatedLinkPreview(proto: proto, builder: defaultBuilder, ownerType: .story, tx: tx)
    }

    public func buildDataSource(
        from draft: OWSLinkPreviewDraft,
        ownerType: TSResourceOwnerType
    ) throws -> LinkPreviewTSResourceDataSource {
        return try buildDataSource(from: draft, builder: defaultBuilder, ownerType: ownerType)
    }

    public func buildDataSource<Builder: LinkPreviewBuilder>(
        from draft: OWSLinkPreviewDraft,
        builder: Builder,
        ownerType: TSResourceOwnerType
    ) throws -> Builder.DataSource {
        let areLinkPreviewsEnabled = db.read { sskPreferences.areLinkPreviewsEnabled(tx: $0) }
        guard areLinkPreviewsEnabled else {
            throw LinkPreviewError.featureDisabled
        }
        return try builder.buildDataSource(draft, ownerType: ownerType)
    }

    public func buildLinkPreview(
        from dataSource: LinkPreviewTSResourceDataSource,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try buildLinkPreview(from: dataSource, builder: defaultBuilder, ownerType: ownerType, tx: tx)
    }

    public func buildLinkPreview<Builder: LinkPreviewBuilder>(
        from dataSource: Builder.DataSource,
        builder: Builder,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard sskPreferences.areLinkPreviewsEnabled(tx: tx) else {
            throw LinkPreviewError.featureDisabled
        }
        return try builder.createLinkPreview(from: dataSource, ownerType: ownerType, tx: tx)
    }

    public func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        let attachmentRef = attachmentStore.linkPreviewAttachment(
            for: parentMessage,
            tx: tx
        )
        return try buildProtoForSending(
            linkPreview,
            previewAttachmentRef: attachmentRef,
            tx: tx
        )
    }

    public func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentStoryMessage: StoryMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        let attachmentRef = attachmentStore.linkPreviewAttachment(
            for: parentStoryMessage,
            tx: tx
        )
        return try buildProtoForSending(
            linkPreview,
            previewAttachmentRef: attachmentRef,
            tx: tx
        )
    }

    // MARK: - Private

    private func fetchLinkPreview(forGenericUrl url: URL) async throws -> OWSLinkPreviewDraft {
        let (respondingUrl, rawHtml) = try await self.fetchStringResource(from: url)

        let content = HTMLMetadata.construct(parsing: rawHtml)
        let rawTitle = content.ogTitle ?? content.titleTag
        let normalizedTitle = rawTitle.map { LinkPreviewHelper.normalizeString($0, maxLines: 2) }
        let draft = OWSLinkPreviewDraft(url: url, title: normalizedTitle)

        let rawDescription = content.ogDescription ?? content.description
        if rawDescription != rawTitle, let description = rawDescription {
            draft.previewDescription = LinkPreviewHelper.normalizeString(description, maxLines: 3)
        }

        draft.date = content.dateForLinkPreview

        if
            let imageUrlString = content.ogImageUrlString ?? content.faviconUrlString,
            let imageUrl = URL(string: imageUrlString, relativeTo: respondingUrl),
            let imageData = try? await self.fetchImageResource(from: imageUrl)
        {
            let previewThumbnail = await Self.previewThumbnail(srcImageData: imageData, srcMimeType: nil)
            draft.imageData = previewThumbnail?.imageData
            draft.imageMimeType = previewThumbnail?.mimetype
        }

        return draft
    }

    // MARK: - Private, Networking

    private func buildOWSURLSession() -> OWSURLSessionProtocol {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.urlCache = nil
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Twitter doesn't return OpenGraph tags to Signal
        // `curl -A Signal "https://twitter.com/signalapp/status/1280166087577997312?s=20"`
        // If this ever changes, we can switch back to our default User-Agent
        let userAgentString = "WhatsApp/2"
        let extraHeaders: [String: String] = [OWSHttpHeaders.userAgentHeaderKey: userAgentString]

        let urlSession = OWSURLSession(
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: sessionConfig,
            extraHeaders: extraHeaders,
            maxResponseSize: Self.maxFetchedContentSize
        )
        urlSession.allowRedirects = true
        urlSession.customRedirectHandler = { request in
            guard request.url.map({ LinkPreviewHelper.isPermittedLinkPreviewUrl($0) }) == true else {
                return nil
            }
            return request
        }
        urlSession.failOnError = false
        return urlSession
    }

    func fetchStringResource(from url: URL) async throws -> (URL, String) {
        let response = try await self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get).awaitable()
        let statusCode = response.responseStatusCode
        guard statusCode >= 200 && statusCode < 300 else {
            Logger.warn("Invalid response: \(statusCode).")
            throw LinkPreviewError.fetchFailure
        }
        guard let string = response.responseBodyString, !string.isEmpty else {
            Logger.warn("Response object could not be parsed")
            throw LinkPreviewError.invalidPreview
        }
        return (response.requestUrl, string)
    }

    private func fetchImageResource(from url: URL) async throws -> Data {
        let httpResponse = try await self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get).awaitable()
        let statusCode = httpResponse.responseStatusCode
        guard statusCode >= 200 && statusCode < 300 else {
            Logger.warn("Invalid response: \(statusCode).")
            throw LinkPreviewError.fetchFailure
        }
        guard let rawData = httpResponse.responseBodyData, rawData.count < Self.maxFetchedContentSize else {
            Logger.warn("Response object could not be parsed")
            throw LinkPreviewError.invalidPreview
        }
        return rawData
    }

    // MARK: - Private, generating from proto

    private func buildValidatedLinkPreview<Builder: LinkPreviewBuilder>(
        proto: SSKProtoPreview,
        builder: Builder,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
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

        let metadata = OWSLinkPreview.Metadata(
            urlString: urlString,
            title: title,
            previewDescription: previewDescription,
            date: date
        )

        guard let protoImage = proto.image else {
            return .withoutFinalizer(.withoutImage(metadata: metadata, ownerType: ownerType))
        }
        return try builder.createLinkPreview(
            from: protoImage,
            metadata: metadata,
            ownerType: ownerType,
            tx: tx
        )
    }

    // MARK: - Private, generating outgoing proto

    private func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        previewAttachmentRef: TSResourceReference?,
        tx: DBReadTransaction
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
            let attachment = attachmentStore.fetch(previewAttachmentRef.resourceId, tx: tx),
            let pointer = attachment.asTransitTierPointer(),
            let attachmentProto = attachmentManager.buildProtoForSending(
                from: previewAttachmentRef,
                pointer: pointer
            )
        {
            builder.setImage(attachmentProto)
        }

        if let date = linkPreview.date {
            builder.setDate(date.ows_millisecondsSince1970)
        }

        return try builder.build()
    }

    // MARK: - Private, Constants

    private static let maxFetchedContentSize = 2 * 1024 * 1024

    // MARK: - Preview Thumbnails

    private struct PreviewThumbnail {
        let imageData: Data
        let mimetype: String
    }

    private static func previewThumbnail(srcImageData: Data?, srcMimeType: String?) async -> PreviewThumbnail? {
        guard let srcImageData = srcImageData else {
            return nil
        }
        let imageMetadata = srcImageData.imageMetadata(withPath: nil, mimeType: srcMimeType)
        guard imageMetadata.isValid else {
            return nil
        }
        let hasValidFormat = imageMetadata.imageFormat != .unknown
        guard hasValidFormat else {
            return nil
        }

        let maxImageSize: CGFloat = 2400

        switch imageMetadata.imageFormat {
        case .unknown:
            owsFailDebug("Invalid imageFormat.")
            return nil
        case .webp:
            guard let stillImage = srcImageData.stillForWebpData() else {
                owsFailDebug("Couldn't derive still image for Webp.")
                return nil
            }

            var stillThumbnail = stillImage
            let imageSize = stillImage.pixelSize
            let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
            if shouldResize {
                guard let resizedImage = stillImage.resized(maxDimensionPixels: maxImageSize) else {
                    owsFailDebug("Couldn't resize image.")
                    return nil
                }
                stillThumbnail = resizedImage
            }

            guard let stillData = stillThumbnail.pngData() else {
                owsFailDebug("Couldn't derive still image for Webp.")
                return nil
            }
            return PreviewThumbnail(imageData: stillData, mimetype: MimeType.imagePng.rawValue)
        default:
            guard let mimeType = imageMetadata.mimeType else {
                owsFailDebug("Unknown mimetype for thumbnail.")
                return nil
            }

            let imageSize = imageMetadata.pixelSize
            let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
            if (imageMetadata.imageFormat == .jpeg || imageMetadata.imageFormat == .png), !shouldResize {
                // If we don't need to resize or convert the file format,
                // return the original data.
                return PreviewThumbnail(imageData: srcImageData, mimetype: mimeType)
            }

            guard let srcImage = UIImage(data: srcImageData) else {
                owsFailDebug("Could not parse image.")
                return nil
            }

            guard let dstImage = srcImage.resized(maxDimensionPixels: maxImageSize) else {
                owsFailDebug("Could not resize image.")
                return nil
            }
            if imageMetadata.hasAlpha {
                guard let dstData = dstImage.pngData() else {
                    owsFailDebug("Could not write resized image to PNG.")
                    return nil
                }
                return PreviewThumbnail(imageData: dstData, mimetype: MimeType.imagePng.rawValue)
            } else {
                guard let dstData = dstImage.jpegData(compressionQuality: 0.8) else {
                    owsFailDebug("Could not write resized image to JPEG.")
                    return nil
                }
                return PreviewThumbnail(imageData: dstData, mimetype: MimeType.imageJpeg.rawValue)
            }
        }
    }

    // MARK: - Stickers

    private func linkPreviewDraft(forStickerShare url: URL) async throws -> OWSLinkPreviewDraft {
        guard let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) else {
            Logger.error("Could not parse url.")
            throw LinkPreviewError.invalidPreview
        }
        // tryToDownloadStickerPack will use locally saved data if possible
        let stickerPack = try await StickerManager.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo).awaitable()
        let coverUrl = try await StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerPack.coverInfo).awaitable()
        let coverData = try Data(contentsOf: coverUrl)
        let previewThumbnail = await Self.previewThumbnail(srcImageData: coverData, srcMimeType: MimeType.imageWebp.rawValue)
        return OWSLinkPreviewDraft(
            url: url,
            title: stickerPack.title?.filterForDisplay,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype
        )
    }

    // MARK: - Group Invite Links

    private func linkPreviewDraft(forGroupInviteLink url: URL) async throws -> OWSLinkPreviewDraft {
        guard let groupInviteLinkInfo = GroupInviteLinkInfo.parseFrom(url) else {
            Logger.error("Could not parse URL.")
            throw LinkPreviewError.invalidPreview
        }
        let groupV2ContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
        let groupInviteLinkPreview = try await self.groupsV2.fetchGroupInviteLinkPreview(
            inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
            groupSecretParams: groupV2ContextInfo.groupSecretParams,
            allowCached: false
        ).awaitable()
        let previewThumbnail: PreviewThumbnail? = await {
            guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                return nil
            }
            let avatarData: Data
            do {
                avatarData = try await self.groupsV2.fetchGroupInviteLinkAvatar(
                    avatarUrlPath: avatarUrlPath,
                    groupSecretParams: groupV2ContextInfo.groupSecretParams
                ).awaitable()
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
                return nil
            }
            return await Self.previewThumbnail(srcImageData: avatarData, srcMimeType: nil)
        }()
        return OWSLinkPreviewDraft(
            url: url,
            title: groupInviteLinkPreview.title,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype
        )
    }
}

fileprivate extension HTMLMetadata {
    var dateForLinkPreview: Date? {
        [ogPublishDateString, articlePublishDateString, ogModifiedDateString, articleModifiedDateString]
            .first(where: {$0 != nil})?
            .flatMap { Date.ows_parseFromISO8601String($0) }
    }
}

extension OWSLinkPreviewDraft {

    fileprivate func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = !titleValue.isEmpty
        }
        let hasImage = imageData != nil && imageMimeType != nil
        return hasTitle || hasImage
    }
}
