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
    var fetchedURLs = [URL]()

    var fetchLinkPreviewBlock: ((URL) async throws -> OWSLinkPreviewDraft)?

    func fetchLinkPreview(for url: URL) async throws -> OWSLinkPreviewDraft {
        fetchedURLs.append(url)
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
        tsAccountManager: any TSAccountManager
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
            linkPreviewDraft = OWSLinkPreviewDraft(url: url, title: linkName)
        } else {
            linkPreviewDraft = try await self.fetchLinkPreview(forGenericUrl: url)
        }
        guard let linkPreviewDraft else {
            throw LinkPreviewError.noPreview
        }
        return linkPreviewDraft
    }

    private func fetchLinkPreview(forGenericUrl url: URL) async throws -> OWSLinkPreviewDraft? {
        let (respondingUrl, rawHtml) = try await self.fetchStringResource(from: url)

        let content = HTMLMetadata.construct(parsing: rawHtml)
        let rawTitle = content.ogTitle ?? content.titleTag
        let normalizedTitle = rawTitle.map { LinkPreviewHelper.normalizeString($0, maxLines: 2) }?.nilIfEmpty
        var rawDescription = content.ogDescription ?? content.description
        if rawDescription == rawTitle {
            rawDescription = nil
        }
        let normalizedDescription = rawDescription.map { LinkPreviewHelper.normalizeString($0, maxLines: 3) }

        var previewThumbnail: PreviewThumbnail?
        if
            let imageUrlString = content.ogImageUrlString ?? content.faviconUrlString,
            let imageUrl = URL(string: imageUrlString, relativeTo: respondingUrl),
            let imageData = try? await self.fetchImageResource(from: imageUrl)
        {
            previewThumbnail = await Self.previewThumbnail(srcImageData: imageData, srcMimeType: nil)
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
            date: content.dateForLinkPreview
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
        return urlSession
    }

    func fetchStringResource(from url: URL) async throws -> (URL, String) {
        let response: any HTTPResponse
        do {
            response = try await self.buildOWSURLSession().performRequest(url.absoluteString, method: .get, ignoreAppExpiry: true)
        } catch {
            Logger.warn("Invalid response: \(error.shortDescription).")
            throw LinkPreviewError.fetchFailure
        }
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
        let response: any HTTPResponse
        do {
            response = try await self.buildOWSURLSession().performRequest(url.absoluteString, method: .get, ignoreAppExpiry: true)
        } catch {
            Logger.warn("Invalid response: \(error.shortDescription).")
            throw LinkPreviewError.fetchFailure
        }
        let statusCode = response.responseStatusCode
        guard statusCode >= 200 && statusCode < 300 else {
            Logger.warn("Invalid response: \(statusCode).")
            throw LinkPreviewError.fetchFailure
        }
        guard let rawData = response.responseBodyData, rawData.count < Self.maxFetchedContentSize else {
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

    private func linkPreviewDraft(forStickerShare url: URL) async throws -> OWSLinkPreviewDraft? {
        guard let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) else {
            Logger.error("Could not parse url.")
            throw LinkPreviewError.invalidPreview
        }
        // tryToDownloadStickerPack will use locally saved data if possible...
        let stickerPack = try await StickerManager.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo).awaitable()
        let title = stickerPack.title?.filterForDisplay.nilIfEmpty
        let coverUrl = try await StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerPack.coverInfo).awaitable()
        let coverData = try Data(contentsOf: coverUrl)
        let previewThumbnail = await Self.previewThumbnail(srcImageData: coverData, srcMimeType: MimeType.imageWebp.rawValue)

        guard title != nil || previewThumbnail != nil else {
            return nil
        }

        return OWSLinkPreviewDraft(
            url: url,
            title: title,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype
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
            allowCached: false
        )
        let previewThumbnail: PreviewThumbnail? = await {
            guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                return nil
            }
            let avatarData: Data
            do {
                avatarData = try await self.groupsV2.fetchGroupInviteLinkAvatar(
                    avatarUrlPath: avatarUrlPath,
                    groupSecretParams: groupV2ContextInfo.groupSecretParams
                )
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
                return nil
            }
            return await Self.previewThumbnail(srcImageData: avatarData, srcMimeType: nil)
        }()

        let title = groupInviteLinkPreview.title.nilIfEmpty
        guard title != nil || previewThumbnail != nil else {
            return nil
        }

        return OWSLinkPreviewDraft(
            url: url,
            title: title,
            imageData: previewThumbnail?.imageData,
            imageMimeType: previewThumbnail?.mimetype
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

fileprivate extension HTMLMetadata {
    var dateForLinkPreview: Date? {
        [ogPublishDateString, articlePublishDateString, ogModifiedDateString, articleModifiedDateString]
            .first(where: {$0 != nil})?
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
