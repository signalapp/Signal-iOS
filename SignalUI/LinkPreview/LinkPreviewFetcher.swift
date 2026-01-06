//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public protocol LinkPreviewFetcher {
    func fetchLinkPreview(for url: URL) async throws -> OWSLinkPreviewDraft
}

#if TESTABLE_BUILD

class MockLinkPreviewFetcher: LinkPreviewFetcher {
    var fetchedURLs: [URL] { _fetchedURLs.get() }
    let _fetchedURLs = AtomicValue<[URL]>([], lock: .init())

    var fetchLinkPreviewBlock: ((URL) async throws -> OWSLinkPreviewDraft)?

    func fetchLinkPreview(for url: URL) async throws -> OWSLinkPreviewDraft {
        _fetchedURLs.update { $0.append(url) }
        return try await fetchLinkPreviewBlock!(url)
    }
}

#endif

public class LinkPreviewFetcherImpl: LinkPreviewFetcher {
    private let authCredentialManager: any AuthCredentialManager
    private let db: any DB
    private let groupsV2: any GroupsV2
    private let linkPreviewSettingStore: LinkPreviewSettingStore
    private let tsAccountManager: any TSAccountManager

    public init(
        authCredentialManager: any AuthCredentialManager,
        db: any DB,
        groupsV2: any GroupsV2,
        linkPreviewSettingStore: LinkPreviewSettingStore,
        tsAccountManager: any TSAccountManager,
    ) {
        self.authCredentialManager = authCredentialManager
        self.db = db
        self.groupsV2 = groupsV2
        self.linkPreviewSettingStore = linkPreviewSettingStore
        self.tsAccountManager = tsAccountManager
    }

    public func fetchLinkPreview(for url: URL) async throws -> OWSLinkPreviewDraft {
        let areLinkPreviewsEnabled: Bool = self.db.read(block: linkPreviewSettingStore.areLinkPreviewsEnabled(tx:))
        guard areLinkPreviewsEnabled else {
            throw LinkPreviewError.featureDisabled
        }

        let linkPreviewDraft: OWSLinkPreviewDraft?
        if StickerPackInfo.isStickerPackShare(url) {
            linkPreviewDraft = try await self.linkPreviewDraft(forStickerShare: url)
        } else if GroupManager.isPossibleGroupInviteLink(url) {
            linkPreviewDraft = try await self.linkPreviewDraft(forGroupInviteLink: url)
        } else if let callLink = CallLink(url: url) {
            let linkName = try await self.fetchName(forCallLink: callLink)
            linkPreviewDraft = OWSLinkPreviewDraft(url: url, title: linkName, isForwarded: false)
        } else {
            linkPreviewDraft = try await self.fetchLinkPreview(forGenericUrl: url)
        }
        guard let linkPreviewDraft else {
            throw LinkPreviewError.noPreview
        }
        return linkPreviewDraft
    }

    private func fetchLinkPreview(forGenericUrl url: URL) async throws -> OWSLinkPreviewDraft? {
        let normalizedTitle: String?
        let normalizedDescription: String?
        let previewThumbnail: PreviewThumbnail?
        let dateForLinkPreview: Date?

        switch try await self.fetchStringOrImageResource(from: url) {
        case .string(let respondingUrl, let rawHtml):
            let content = HTMLMetadata.construct(parsing: rawHtml)
            let rawTitle = content.ogTitle ?? content.titleTag
            normalizedTitle = rawTitle.map { LinkPreviewHelper.normalizeString($0, maxLines: 2) }?.nilIfEmpty
            var rawDescription = content.ogDescription ?? content.description
            if rawDescription == rawTitle {
                rawDescription = nil
            }
            normalizedDescription = rawDescription.map { LinkPreviewHelper.normalizeString($0, maxLines: 3) }
            dateForLinkPreview = content.dateForLinkPreview

            if
                let imageUrlString = content.ogImageUrlString ?? content.faviconUrlString,
                let imageUrl = URL(string: imageUrlString, relativeTo: respondingUrl),
                let imageData = try? await self.fetchImageResource(from: imageUrl)
            {
                previewThumbnail = await Self.previewThumbnail(srcImageData: imageData)
            } else {
                previewThumbnail = nil
            }

        case .image(let url, let contents):
            previewThumbnail = await Self.previewThumbnail(srcImageData: contents)
            normalizedDescription = nil
            dateForLinkPreview = nil
            normalizedTitle = if previewThumbnail != nil {
                // The best we can do for a title is the filename in the URL itself,
                // but that's no worse than the body of the message.
                url.lastPathComponent.filterStringForDisplay().nilIfEmpty
            } else {
                nil
            }
        }

        guard normalizedTitle != nil || previewThumbnail != nil else {
            return nil
        }

        return OWSLinkPreviewDraft(
            url: url,
            title: normalizedTitle,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype,
            previewDescription: normalizedDescription,
            date: dateForLinkPreview,
            isForwarded: false,
        )
    }

    private func buildOWSURLSession() -> OWSURLSessionProtocol {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.urlCache = nil
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Twitter doesn't return OpenGraph tags to Signal
        // `curl -A Signal "https://twitter.com/signalapp/status/1280166087577997312?s=20"`
        // If this ever changes, we can switch back to our default User-Agent
        let userAgentString = "WhatsApp/2"
        let extraHeaders: HttpHeaders = [HttpHeaders.userAgentHeaderKey: userAgentString]

        let urlSession = OWSURLSession(
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: sessionConfig,
            extraHeaders: extraHeaders,
            maxResponseSize: Self.maxFetchedContentSize,
        )
        urlSession.allowRedirects = true
        urlSession.customRedirectHandler = { request in
            guard request.url.map({ LinkPreviewHelper.isPermittedLinkPreviewUrl($0) }) == true else {
                return nil
            }
            return request
        }
        return urlSession
    }

    enum StringOrImageResource {
        case string(url: URL, contents: String)
        case image(url: URL, contents: Data)

        static func dataForImage(_ response: HTTPResponse) -> Data? {
            guard let rawData = response.responseBodyData, rawData.count < maxFetchedContentSize else {
                return nil
            }
            return rawData
        }
    }

    func fetchStringOrImageResource(from url: URL) async throws -> StringOrImageResource {
        let response: HTTPResponse
        do {
            response = try await self.buildOWSURLSession().performRequest(url.absoluteString, method: .get, ignoreAppExpiry: true)
        } catch {
            Logger.warn("Invalid response: \(error.shortDescription).")
            throw LinkPreviewError.fetchFailure
        }
        let statusCode = response.responseStatusCode
        guard statusCode >= 200, statusCode < 300 else {
            Logger.warn("Invalid response: \(statusCode).")
            throw LinkPreviewError.fetchFailure
        }

        // TODO: Add support for HEIC, HEIF, JPEG XL, etc.
        if
            let mimeType = response.headers.value(forHeader: "Content-Type"),
            MimeTypeUtil.isSupportedImageMimeType(mimeType)
        {
            guard let imageData = StringOrImageResource.dataForImage(response) else {
                Logger.warn("Response object could not be parsed")
                throw LinkPreviewError.invalidPreview
            }
            return .image(url: response.requestUrl, contents: imageData)
        }

        guard let string = response.responseBodyString, !string.isEmpty else {
            Logger.warn("Response object could not be parsed")
            throw LinkPreviewError.invalidPreview
        }
        return .string(url: response.requestUrl, contents: string)
    }

    private func fetchImageResource(from url: URL) async throws -> Data {
        let response: HTTPResponse
        do {
            response = try await self.buildOWSURLSession().performRequest(url.absoluteString, method: .get, ignoreAppExpiry: true)
        } catch {
            Logger.warn("Invalid response: \(error.shortDescription).")
            throw LinkPreviewError.fetchFailure
        }
        let statusCode = response.responseStatusCode
        guard statusCode >= 200, statusCode < 300 else {
            Logger.warn("Invalid response: \(statusCode).")
            throw LinkPreviewError.fetchFailure
        }
        guard let rawData = StringOrImageResource.dataForImage(response) else {
            Logger.warn("Response object could not be parsed")
            throw LinkPreviewError.invalidPreview
        }
        return rawData
    }

    // MARK: - Private, Constants

    private static let maxFetchedContentSize = 2 * 1024 * 1024

    // MARK: - Preview Thumbnails

    private struct PreviewThumbnail {
        let imageData: Data
        let mimetype: String
    }

    private static func previewThumbnail(srcImageData: Data?) async -> PreviewThumbnail? {
        guard let srcImageData else {
            return nil
        }
        let imageSource = DataImageSource(srcImageData)
        let imageMetadata = imageSource.imageMetadata()
        guard let imageMetadata else {
            return nil
        }
        let imageFormat = imageMetadata.imageFormat

        let maxImageSize: CGFloat = 2400

        switch imageFormat {
        case .webp:
            guard let stillImage = imageSource.stillForWebpData() else {
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
            let mimeType = imageFormat.mimeType

            let imageSize = imageMetadata.pixelSize
            let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
            if imageMetadata.imageFormat == .jpeg || imageMetadata.imageFormat == .png, !shouldResize {
                // If we don't need to resize or convert the file format,
                // return the original data.
                return PreviewThumbnail(imageData: srcImageData, mimetype: mimeType.rawValue)
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

    private func linkPreviewDraft(forStickerShare url: URL) async throws -> OWSLinkPreviewDraft? {
        guard let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) else {
            Logger.error("Could not parse url.")
            throw LinkPreviewError.invalidPreview
        }
        // tryToDownloadStickerPack will use locally saved data if possible...
        let stickerPack = try await StickerManager.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo).awaitable()
        let title = stickerPack.title?.filterForDisplay.nilIfEmpty
        let coverUrl = try await StickerManager.tryToDownloadSticker(stickerInfo: stickerPack.coverInfo).awaitable()
        let coverData = try Data(contentsOf: coverUrl)
        let previewThumbnail = await Self.previewThumbnail(srcImageData: coverData)

        guard title != nil || previewThumbnail != nil else {
            return nil
        }

        return OWSLinkPreviewDraft(
            url: url,
            title: title,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype,
            isForwarded: false,
        )
    }

    // MARK: - Group Invite Links

    private func linkPreviewDraft(forGroupInviteLink url: URL) async throws -> OWSLinkPreviewDraft? {
        guard let groupInviteLinkInfo = GroupInviteLinkInfo.parseFrom(url) else {
            Logger.error("Could not parse URL.")
            throw LinkPreviewError.invalidPreview
        }
        let groupV2ContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
        let groupInviteLinkPreview = try await self.groupsV2.fetchGroupInviteLinkPreview(
            inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
            groupSecretParams: groupV2ContextInfo.groupSecretParams,
        )
        let previewThumbnail: PreviewThumbnail? = await {
            guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                return nil
            }
            let avatarData: Data
            do {
                avatarData = try await self.groupsV2.fetchGroupInviteLinkAvatar(
                    avatarUrlPath: avatarUrlPath,
                    groupSecretParams: groupV2ContextInfo.groupSecretParams,
                )
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
                return nil
            }
            return await Self.previewThumbnail(srcImageData: avatarData)
        }()

        let title = groupInviteLinkPreview.title.nilIfEmpty
        guard title != nil || previewThumbnail != nil else {
            return nil
        }

        return OWSLinkPreviewDraft(
            url: url,
            title: title,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype,
            isForwarded: false,
        )
    }

    // MARK: - Call Links

    private func fetchName(forCallLink callLink: CallLink) async throws -> String? {
        let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
        let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        let callLinkState = try await CallLinkFetcherImpl().readCallLink(callLink.rootKey, authCredential: authCredential)
        return callLinkState.name
    }
}

private extension HTMLMetadata {
    var dateForLinkPreview: Date? {
        [ogPublishDateString, articlePublishDateString, ogModifiedDateString, articleModifiedDateString]
            .first(where: { $0 != nil })?
            .flatMap {
                guard
                    let date = Date.ows_parseFromISO8601String($0),
                    date.timeIntervalSince1970 > 0
                else {
                    return nil
                }
                return date
            }
    }
}
