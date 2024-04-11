//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class LinkPreviewManagerImpl: LinkPreviewManager {

    // Although link preview fetches are non-blocking, the user may still end up
    // waiting for the fetch to complete. Because of this, UserInitiated is likely
    // most appropriate QoS.
    private static let workQueue: DispatchQueue = .sharedUserInitiated

    private let attachmentManager: TSResourceManager
    private let attachmentStore: TSResourceStore
    private let db: DB
    private let groupsV2: Shims.GroupsV2
    private let sskPreferences: Shims.SSKPreferences

    public init(
        attachmentManager: TSResourceManager,
        attachmentStore: TSResourceStore,
        db: DB,
        groupsV2: Shims.GroupsV2,
        sskPreferences: Shims.SSKPreferences
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.db = db
        self.groupsV2 = groupsV2
        self.sskPreferences = sskPreferences
    }

    private lazy var defaultBuilder = LinkPreviewTSResourceBuilder(tsResourceManager: attachmentManager)

    // MARK: - Public

    public func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool {
        sskPreferences.areLinkPreviewsEnabled(tx: tx)
    }

    public func fetchLinkPreview(for url: URL) -> Promise<OWSLinkPreviewDraft> {
        return firstly(on: Self.workQueue) { () -> Promise<OWSLinkPreviewDraft> in
            let areLinkPreviewsEnabled: Bool = self.db.read(block: self.areLinkPreviewsEnabled(tx:))
            guard areLinkPreviewsEnabled else {
                return Promise(error: LinkPreviewError.featureDisabled)
            }

            if StickerPackInfo.isStickerPackShare(url) {
                return self.linkPreviewDraft(forStickerShare: url)
            } else if GroupManager.isPossibleGroupInviteLink(url) {
                return self.linkPreviewDraft(forGroupInviteLink: url)
            } else {
                return self.fetchLinkPreview(forGenericUrl: url)
            }
        }.map(on: Self.workQueue) { (linkPreviewDraft) -> OWSLinkPreviewDraft in
            guard linkPreviewDraft.isValid() else {
                throw LinkPreviewError.noPreview
            }
            return linkPreviewDraft
        }
    }

    public func validateAndBuildLinkPreview(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try validateAndBuildLinkPreview(
            from: proto,
            dataMessage: dataMessage,
            builder: defaultBuilder,
            tx: tx
        )
    }

    public func validateAndBuildLinkPreview<Builder: LinkPreviewBuilder>(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        builder: Builder,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard dataMessage.attachments.count < 1 else {
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

        return try buildValidatedLinkPreview(proto: proto, builder: defaultBuilder, tx: tx)
    }

    public func validateAndBuildStoryLinkPreview(
        from proto: SSKProtoPreview,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard LinkValidator.isValidLink(linkText: proto.url) else {
            Logger.error("Discarding link preview; can't parse URLs in story message.")
            throw LinkPreviewError.invalidPreview
        }
        return try buildValidatedLinkPreview(proto: proto, builder: defaultBuilder, tx: tx)
    }

    public func validateAndBuildLinkPreview(
        from draft: OWSLinkPreviewDraft,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try self.validateAndBuildLinkPreview(
            from: draft,
            builder: defaultBuilder,
            tx: tx
        )
    }

    public func validateAndBuildLinkPreview<Builder: LinkPreviewBuilder>(
        from draft: OWSLinkPreviewDraft,
        builder: Builder,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard sskPreferences.areLinkPreviewsEnabled(tx: tx) else {
            throw LinkPreviewError.featureDisabled
        }

        let metadata = OWSLinkPreview.Metadata(
            urlString: draft.urlString,
            title: draft.title,
            previewDescription: draft.previewDescription,
            date: draft.date
        )

        guard
            let imageData = draft.imageData,
            let imageMimeType = draft.imageMimeType
        else {
            return .withoutFinalizer(.withoutImage(metadata: metadata))
        }

        let dataSource = Builder.buildAttachmentDataSource(
            data: imageData,
            mimeType: imageMimeType
        )
        return try builder.createLinkPreview(
            from: dataSource,
            metadata: metadata,
            tx: tx
        )
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

    private func fetchLinkPreview(forGenericUrl url: URL) -> Promise<OWSLinkPreviewDraft> {
        firstly(on: Self.workQueue) { () -> Promise<(URL, String)> in
            self.fetchStringResource(from: url)

        }.then(on: Self.workQueue) { (respondingUrl, rawHTML) -> Promise<OWSLinkPreviewDraft> in
            let content = HTMLMetadata.construct(parsing: rawHTML)
            let rawTitle = content.ogTitle ?? content.titleTag
            let normalizedTitle = rawTitle.map { LinkPreviewHelper.normalizeString($0, maxLines: 2) }
            let draft = OWSLinkPreviewDraft(url: url, title: normalizedTitle)

            let rawDescription = content.ogDescription ?? content.description
            if rawDescription != rawTitle, let description = rawDescription {
                draft.previewDescription = LinkPreviewHelper.normalizeString(description, maxLines: 3)
            }

            draft.date = content.dateForLinkPreview

            guard let imageUrlString = content.ogImageUrlString ?? content.faviconUrlString,
                  let imageUrl = URL(string: imageUrlString, relativeTo: respondingUrl) else {
                return Promise.value(draft)
            }

            return firstly(on: Self.workQueue) { () -> Promise<Data> in
                self.fetchImageResource(from: imageUrl)
            }.then(on: Self.workQueue) { (imageData: Data) -> Promise<PreviewThumbnail?> in
                Self.previewThumbnail(srcImageData: imageData, srcMimeType: nil)
            }.map(on: Self.workQueue) { (previewThumbnail: PreviewThumbnail?) -> OWSLinkPreviewDraft in
                guard let previewThumbnail = previewThumbnail else {
                    return draft
                }
                draft.imageData = previewThumbnail.imageData
                draft.imageMimeType = previewThumbnail.mimetype
                return draft
            }.recover(on: Self.workQueue) { (_) -> Promise<OWSLinkPreviewDraft> in
                return Promise.value(draft)
            }
        }
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

    func fetchStringResource(from url: URL) -> Promise<(URL, String)> {
        firstly(on: Self.workQueue) { () -> Promise<(HTTPResponse)> in
            self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get)
        }.map(on: Self.workQueue) { (response: HTTPResponse) -> (URL, String) in
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
    }

    private func fetchImageResource(from url: URL) -> Promise<Data> {
        firstly(on: Self.workQueue) { () -> Promise<(HTTPResponse)> in
            self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get)
        }.map(on: Self.workQueue) { (httpResponse: HTTPResponse) -> Data in
            try autoreleasepool {
                let statusCode = httpResponse.responseStatusCode
                guard statusCode >= 200 && statusCode < 300 else {
                    Logger.warn("Invalid response: \(statusCode).")
                    throw LinkPreviewError.fetchFailure
                }
                guard let rawData = httpResponse.responseBodyData,
                      rawData.count < Self.maxFetchedContentSize else {
                    Logger.warn("Response object could not be parsed")
                    throw LinkPreviewError.invalidPreview
                }
                return rawData
            }
        }
    }

    // MARK: - Private, generating from proto

    private func buildValidatedLinkPreview<Builder: LinkPreviewBuilder>(
        proto: SSKProtoPreview,
        builder: Builder,
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
            return .withoutFinalizer(.withoutImage(metadata: metadata))
        }
        return try builder.createLinkPreview(
            from: protoImage,
            metadata: metadata,
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

    private static func previewThumbnail(srcImageData: Data?, srcMimeType: String?) -> Promise<PreviewThumbnail?> {
        guard let srcImageData = srcImageData else {
            return Promise.value(nil)
        }
        return firstly(on: Self.workQueue) { () -> PreviewThumbnail? in
            let imageMetadata = (srcImageData as NSData).imageMetadata(withPath: nil, mimeType: srcMimeType)
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
                guard let stillImage = (srcImageData as NSData).stillForWebpData() else {
                    owsFailDebug("Couldn't derive still image for Webp.")
                    return nil
                }

                var stillThumbnail = stillImage
                let imageSize = stillImage.pixelSize
                let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
                if shouldResize {
                    guard let resizedImage = stillImage.resized(withMaxDimensionPixels: maxImageSize) else {
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
                if (imageMetadata.imageFormat == .jpeg || imageMetadata.imageFormat == .png),
                    !shouldResize {
                    // If we don't need to resize or convert the file format,
                    // return the original data.
                    return PreviewThumbnail(imageData: srcImageData, mimetype: mimeType)
                }

                guard let srcImage = UIImage(data: srcImageData) else {
                    owsFailDebug("Could not parse image.")
                    return nil
                }

                guard let dstImage = srcImage.resized(withMaxDimensionPixels: maxImageSize) else {
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
    }

    // MARK: - Stickers

    private func linkPreviewDraft(forStickerShare url: URL) -> Promise<OWSLinkPreviewDraft> {
        guard let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) else {
            Logger.error("Could not parse url.")
            return Promise(error: LinkPreviewError.invalidPreview)
        }

        // tryToDownloadStickerPack will use locally saved data if possible.
        return firstly(on: Self.workQueue) {
            StickerManager.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
        }.then(on: Self.workQueue) { (stickerPack: StickerPack) -> Promise<OWSLinkPreviewDraft> in
            let coverInfo = stickerPack.coverInfo
            // tryToDownloadSticker will use locally saved data if possible.
            return firstly { () -> Promise<URL> in
                StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: coverInfo)
            }.map(on: Self.workQueue) { (coverUrl: URL) in
                return try Data(contentsOf: coverUrl)
            }.then(on: Self.workQueue) { (coverData) -> Promise<PreviewThumbnail?> in
                Self.previewThumbnail(srcImageData: coverData, srcMimeType: MimeType.imageWebp.rawValue)
            }.map(on: Self.workQueue) { (previewThumbnail: PreviewThumbnail?) -> OWSLinkPreviewDraft in
                guard let previewThumbnail = previewThumbnail else {
                    return OWSLinkPreviewDraft(url: url,
                                               title: stickerPack.title?.filterForDisplay)
                }
                return OWSLinkPreviewDraft(url: url,
                                           title: stickerPack.title?.filterForDisplay,
                                           imageData: previewThumbnail.imageData,
                                           imageMimeType: previewThumbnail.mimetype)
            }
        }
    }

    // MARK: - Group Invite Links

    private func linkPreviewDraft(forGroupInviteLink url: URL) -> Promise<OWSLinkPreviewDraft> {
        return firstly(on: Self.workQueue) { () -> GroupInviteLinkInfo in
            guard let groupInviteLinkInfo = GroupManager.parseGroupInviteLink(url) else {
                Logger.error("Could not parse URL.")
                throw LinkPreviewError.invalidPreview
            }
            return groupInviteLinkInfo
        }.then(on: Self.workQueue) { (groupInviteLinkInfo: GroupInviteLinkInfo) -> Promise<OWSLinkPreviewDraft> in
            let groupV2ContextInfo = try self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
            return firstly {
                self.groupsV2.fetchGroupInviteLinkPreview(
                    inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                    groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData,
                    allowCached: false
                )
            }.then(on: Self.workQueue) { (groupInviteLinkPreview: GroupInviteLinkPreview) in
                return firstly { () -> Promise<Data?> in
                    guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                        return Promise.value(nil)
                    }
                    return firstly { () -> Promise<Data> in
                        self.groupsV2.fetchGroupInviteLinkAvatar(
                            avatarUrlPath: avatarUrlPath,
                            groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData
                        )
                    }.map { (avatarData: Data) -> Data? in
                        return avatarData
                    }.recover { (error: Error) -> Promise<Data?> in
                        owsFailDebugUnlessNetworkFailure(error)
                        return Promise.value(nil)
                    }
                }.then(on: Self.workQueue) { (imageData: Data?) -> Promise<PreviewThumbnail?> in
                    Self.previewThumbnail(srcImageData: imageData, srcMimeType: nil)
                }.map(on: Self.workQueue) { (previewThumbnail: PreviewThumbnail?) -> OWSLinkPreviewDraft in
                    guard let previewThumbnail = previewThumbnail else {
                        return OWSLinkPreviewDraft(url: url,
                                                   title: groupInviteLinkPreview.title)
                    }
                    return OWSLinkPreviewDraft(url: url,
                                               title: groupInviteLinkPreview.title,
                                               imageData: previewThumbnail.imageData,
                                               imageMimeType: previewThumbnail.mimetype)
                }
            }
        }
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
