//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkPreviewError: Int, Error {
    /// A preview could not be generated from available input
    case noPreview
    /// A preview should have been generated, but something unexpected caused it to fail
    case invalidPreview
    /// A preview could not be generated due to an issue fetching a network resource
    case fetchFailure
    /// A preview could not be generated because the feature is disabled
    case featureDisabled
}

// MARK: - OWSLinkPreviewDraft

// This contains the info for a link preview "draft".
public class OWSLinkPreviewDraft: NSObject {

    public var url: URL
    public var urlString: String {
        return url.absoluteString
    }
    public var title: String?
    public var imageData: Data?
    public var imageMimeType: String?
    public var previewDescription: String?
    public var date: Date?

    public init(url: URL, title: String?, imageData: Data? = nil, imageMimeType: String? = nil) {
        self.url = url
        self.title = title
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }

    fileprivate func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = !titleValue.isEmpty
        }
        let hasImage = imageData != nil && imageMimeType != nil
        return hasTitle || hasImage
    }

    public var displayDomain: String? {
        OWSLinkPreviewManager.displayDomain(forUrl: urlString)
    }
}

// MARK: - OWSLinkPreview

@objc
public class OWSLinkPreview: MTLModel, Codable {

    @objc
    public var urlString: String?

    @objc
    public var title: String?

    @objc
    public var imageAttachmentId: String?

    @objc
    public var previewDescription: String?

    @objc
    public var date: Date?

    public init(urlString: String, title: String?, imageAttachmentId: String?) {
        self.urlString = urlString
        self.title = title
        self.imageAttachmentId = imageAttachmentId

        super.init()
    }

    public override init() {
        super.init()
    }

    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public class func isNoPreviewError(_ error: Error) -> Bool {
        guard let error = error as? LinkPreviewError else {
            return false
        }
        return error == .noPreview
    }

    @objc
    public class func buildValidatedLinkPreview(
        dataMessage: SSKProtoDataMessage,
        body: String?,
        transaction: SDSAnyWriteTransaction
    ) throws -> OWSLinkPreview {
        guard let previewProto = dataMessage.preview.first else {
            throw LinkPreviewError.noPreview
        }
        guard dataMessage.attachments.count < 1 else {
            Logger.error("Discarding link preview; message has attachments.")
            throw LinkPreviewError.invalidPreview
        }
        guard let body = body, body.contains(previewProto.url) else {
            Logger.error("Url not present in body")
            throw LinkPreviewError.invalidPreview
        }

       return try buildValidatedLinkPreview(proto: previewProto, transaction: transaction)
    }

    public class func buildValidatedLinkPreview(
        proto: SSKProtoPreview,
        transaction: SDSAnyWriteTransaction
    ) throws -> OWSLinkPreview {
        let urlString = proto.url

        guard let url = URL(string: urlString), url.isPermittedLinkPreviewUrl() else {
            Logger.error("Could not parse preview url.")
            throw LinkPreviewError.invalidPreview
        }

        var title: String?
        var previewDescription: String?
        if let rawTitle = proto.title {
            let normalizedTitle = normalizeString(rawTitle, maxLines: 2)
            if !normalizedTitle.isEmpty {
                title = normalizedTitle
            }
        }
        if let rawDescription = proto.previewDescription, proto.title != proto.previewDescription {
            let normalizedDescription = normalizeString(rawDescription, maxLines: 3)
            if !normalizedDescription.isEmpty {
                previewDescription = normalizedDescription
            }
        }

        var imageAttachmentId: String?
        if let imageProto = proto.image {
            if let imageAttachmentPointer = TSAttachmentPointer(fromProto: imageProto, albumMessage: nil) {
                imageAttachmentPointer.anyInsert(transaction: transaction)
                imageAttachmentId = imageAttachmentPointer.uniqueId
            } else {
                Logger.error("Could not parse image proto.")
                throw LinkPreviewError.invalidPreview
            }
        }

        let linkPreview = OWSLinkPreview(urlString: urlString, title: title, imageAttachmentId: imageAttachmentId)
        linkPreview.previewDescription = previewDescription

        // Zero check required. Some devices in the wild will explicitly set zero to mean "no date"
        if proto.hasDate, proto.date > 0 {
            linkPreview.date = Date(millisecondsSince1970: proto.date)
        }

        return linkPreview
    }

    public class func buildValidatedLinkPreview(fromInfo info: OWSLinkPreviewDraft,
                                                transaction: SDSAnyWriteTransaction) throws -> OWSLinkPreview {
        guard SSKPreferences.areLinkPreviewsEnabled(transaction: transaction) else {
            throw LinkPreviewError.featureDisabled
        }
        let imageAttachmentId = OWSLinkPreview.saveAttachmentIfPossible(imageData: info.imageData,
                                                                        imageMimeType: info.imageMimeType,
                                                                        transaction: transaction)

        let linkPreview = OWSLinkPreview(urlString: info.urlString, title: info.title, imageAttachmentId: imageAttachmentId)
        linkPreview.previewDescription = info.previewDescription
        linkPreview.date = info.date
        return linkPreview
    }

    public func buildProto(transaction: SDSAnyReadTransaction) throws -> SSKProtoPreview {
        guard let urlString = urlString else {
            Logger.error("Preview does not have url.")
            throw LinkPreviewError.invalidPreview
        }

        let builder = SSKProtoPreview.builder(url: urlString)

        if let title = title {
            builder.setTitle(title)
        }

        if let previewDescription = previewDescription {
            builder.setPreviewDescription(previewDescription)
        }

        if
            let imageAttachmentId = imageAttachmentId,
            let attachmentProto = TSAttachmentStream.buildProto(forAttachmentId: imageAttachmentId, transaction: transaction)
        {
            builder.setImage(attachmentProto)
        }

        if let date = date {
            builder.setDate(date.ows_millisecondsSince1970)
        }

        return try builder.build()
    }

    private class func saveAttachmentIfPossible(imageData: Data?,
                                                imageMimeType: String?,
                                                transaction: SDSAnyWriteTransaction) -> String? {
        guard let imageData = imageData else {
            return nil
        }
        guard let imageMimeType = imageMimeType else {
            return nil
        }
        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: imageMimeType) else {
            return nil
        }
        let fileSize = imageData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for image data.")
            return nil
        }
        let contentType = imageMimeType

        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension)
        do {
            try imageData.write(to: fileUrl)
            let dataSource = try DataSourcePath.dataSource(with: fileUrl, shouldDeleteOnDeallocation: true)
            let attachment = TSAttachmentStream(contentType: contentType, byteCount: UInt32(fileSize), sourceFilename: nil, caption: nil, albumMessageId: nil)
            try attachment.writeConsumingDataSource(dataSource)
            attachment.anyInsert(transaction: transaction)

            return attachment.uniqueId
        } catch {
            owsFailDebug("Could not write data source for: \(fileUrl), error: \(error)")
            return nil
        }
    }

    public func removeAttachment(transaction: SDSAnyWriteTransaction) {
        guard let imageAttachmentId = imageAttachmentId else {
            owsFailDebug("No attachment id.")
            return
        }
        guard let attachment = TSAttachment.anyFetch(uniqueId: imageAttachmentId, transaction: transaction) else {
            owsFailDebug("Could not load attachment.")
            return
        }
        attachment.anyRemove(transaction: transaction)
    }

    public var displayDomain: String? {
        OWSLinkPreviewManager.displayDomain(forUrl: urlString)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case urlString, title, imageAttachmentId, previewDescription, date
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        imageAttachmentId = try container.decodeIfPresent(String.self, forKey: .imageAttachmentId)
        previewDescription = try container.decodeIfPresent(String.self, forKey: .previewDescription)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let urlString = urlString {
            try container.encode(urlString, forKey: .urlString)
        }
        if let title = title {
            try container.encode(title, forKey: .title)
        }
        if let imageAttachmentId = imageAttachmentId {
            try container.encode(imageAttachmentId, forKey: .imageAttachmentId)
        }
        if let previewDescription = previewDescription {
            try container.encode(previewDescription, forKey: .previewDescription)
        }
        if let date = date {
            try container.encode(date, forKey: .date)
        }
    }
}

// MARK: -

@objc
public class OWSLinkPreviewManager: NSObject, Dependencies {

    // Although link preview fetches are non-blocking, the user may still end up
    // waiting for the fetch to complete. Because of this, UserInitiated is likely
    // most appropriate QoS.
    static let workQueue: DispatchQueue = .sharedUserInitiated

    // MARK: - Public

    public func findFirstValidUrl(in searchString: String, bypassSettingsCheck: Bool) -> URL? {
        guard bypassSettingsCheck || areLinkPreviewsEnabledWithSneakyTransaction() else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            owsFailDebug("Could not create NSDataDetector")
            return nil
        }

        var result: URL?
        detector.enumerateMatches(in: searchString, range: searchString.entireRange) { match, _, stop in
            guard let match = match else { return }
            guard let parsedUrl = match.url else { return }
            guard let matchedRange = Range(match.range, in: searchString) else { return }
            let matchedString = String(searchString[matchedRange])
            if parsedUrl.isPermittedLinkPreviewUrl(parsedFrom: matchedString) {
                result = parsedUrl
                stop.pointee = true
            }
        }
        return result
    }

    public func fetchLinkPreview(for url: URL) -> Promise<OWSLinkPreviewDraft> {
        guard areLinkPreviewsEnabledWithSneakyTransaction() else {
            return Promise(error: LinkPreviewError.featureDisabled)
        }

        return firstly(on: Self.workQueue) { () -> Promise<OWSLinkPreviewDraft> in
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

    // MARK: - Private

    private func fetchLinkPreview(forGenericUrl url: URL) -> Promise<OWSLinkPreviewDraft> {
        firstly(on: Self.workQueue) { () -> Promise<(URL, String)> in
            self.fetchStringResource(from: url)

        }.then(on: Self.workQueue) { (respondingUrl, rawHTML) -> Promise<OWSLinkPreviewDraft> in
            let content = HTMLMetadata.construct(parsing: rawHTML)
            let rawTitle = content.ogTitle ?? content.titleTag
            let normalizedTitle = rawTitle.map { normalizeString($0, maxLines: 2) }
            let draft = OWSLinkPreviewDraft(url: url, title: normalizedTitle)

            let rawDescription = content.ogDescription ?? content.description
            if rawDescription != rawTitle, let description = rawDescription {
                draft.previewDescription = normalizeString(description, maxLines: 3)
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

    // MARK: - Private, Utilities

    func areLinkPreviewsEnabledWithSneakyTransaction() -> Bool {
        return databaseStorage.read { transaction in
            SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
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
            guard request.url?.isPermittedLinkPreviewUrl() == true else {
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

    // MARK: - Private, Constants

    private static let maxFetchedContentSize = 2 * 1024 * 1024
    private static let allowedMIMETypes: Set = [OWSMimeTypeImagePng, OWSMimeTypeImageJpeg]

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
                return PreviewThumbnail(imageData: stillData, mimetype: OWSMimeTypeImagePng)
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
                    return PreviewThumbnail(imageData: dstData, mimetype: OWSMimeTypeImagePng)
                } else {
                    guard let dstData = dstImage.jpegData(compressionQuality: 0.8) else {
                        owsFailDebug("Could not write resized image to JPEG.")
                        return nil
                    }
                    return PreviewThumbnail(imageData: dstData, mimetype: OWSMimeTypeImageJpeg)
                }
            }
        }
    }

    // MARK: - Stickers

    private func linkPreviewDraft(forStickerShare url: URL) -> Promise<OWSLinkPreviewDraft> {
        Logger.verbose("url: \(url)")

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
                Self.previewThumbnail(srcImageData: coverData, srcMimeType: OWSMimeTypeImageWebp)
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
        Logger.verbose("url: \(url)")

        return firstly(on: Self.workQueue) { () -> GroupInviteLinkInfo in
            guard let groupInviteLinkInfo = GroupManager.parseGroupInviteLink(url) else {
                Logger.error("Could not parse URL.")
                throw LinkPreviewError.invalidPreview
            }
            return groupInviteLinkInfo
        }.then(on: Self.workQueue) { (groupInviteLinkInfo: GroupInviteLinkInfo) -> Promise<OWSLinkPreviewDraft> in
            let groupV2ContextInfo = try self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
            return firstly {
                Self.groupsV2Swift.fetchGroupInviteLinkPreview(inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                                                               groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData,
                                                               allowCached: false)
            }.then(on: Self.workQueue) { (groupInviteLinkPreview: GroupInviteLinkPreview) in
                return firstly { () -> Promise<Data?> in
                    guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                        return Promise.value(nil)
                    }
                    return firstly { () -> Promise<Data> in
                        self.groupsV2Swift.fetchGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath,
                                                                      groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData)
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

fileprivate extension URL {
    private static let schemeAllowSet: Set = ["https"]
    private static let tldRejectSet: Set = ["onion", "i2p"]
    private static let urlDelimeters: Set<Character> = Set(":/?#[]@")

    var mimeType: String? {
        if pathExtension.isEmpty {
            return nil
        }
        guard let mimeType = MIMETypeUtil.mimeType(forFileExtension: pathExtension) else {
            Logger.error("Image url has unknown content type: \(pathExtension).")
            return nil
        }
        return mimeType
    }

    /// Helper method that validates:
    /// - TLD is permitted
    /// - Comprised of valid character set
    static private func isValidHostname(_ hostname: String) -> Bool {
        // Technically, a TLD separator can be something other than a period (e.g. https://一二三。中国)
        // But it looks like NSURL/NSDataDetector won't even parse that. So we'll require periods for now
        let hostnameComponents = hostname.split(separator: ".")
        guard hostnameComponents.count >= 2, let tld = hostnameComponents.last?.lowercased() else {
            return false
        }
        let isValidTLD = !Self.tldRejectSet.contains(tld)
        let isAllASCII = hostname.allSatisfy { $0.isASCII }
        let isAllNonASCII = hostname.allSatisfy { !$0.isASCII || $0 == "." }

        return isValidTLD && (isAllASCII || isAllNonASCII)
    }

    /// - Parameter sourceString: The raw string that this URL was parsed from
    /// The source string will be parsed to ensure that the parsed hostname has only ASCII or non-ASCII characters
    /// to avoid homograph URLs.
    ///
    /// The source string is necessary, since NSURL and NSDataDetector will automatically punycode any returned
    /// URLs. The source string will be used to verify that the originating string's host only contained ASCII or
    /// non-ASCII characters to avoid homographs.
    ///
    /// If no sourceString is provided, the validated host will be whatever is returned from `host`, which will always
    /// be ASCII.
    func isPermittedLinkPreviewUrl(parsedFrom sourceString: String? = nil) -> Bool {
        guard let scheme = scheme?.lowercased().nilIfEmpty else { return false }
        guard user == nil else { return false }
        guard password == nil else { return false }
        let rawHostname: String?

        if var sourceString = sourceString {
            let schemePrefix = "\(scheme)://"
            if let schemeRange = sourceString.range(of: schemePrefix, options: [ .anchored, .caseInsensitive ]) {
                sourceString.removeSubrange(schemeRange)
            }

            rawHostname = sourceString
                .split(maxSplits: 1, whereSeparator: { Self.urlDelimeters.contains($0) }).first
                .map { String($0) }
        } else {
            // The hostname will be punycode and all ASCII
            rawHostname = host
        }

        guard let hostnameToValidate = rawHostname else { return false }
        return Self.schemeAllowSet.contains(scheme) && Self.isValidHostname(hostnameToValidate)
    }
}

fileprivate extension HTMLMetadata {
    var dateForLinkPreview: Date? {
        [ogPublishDateString, articlePublishDateString, ogModifiedDateString, articleModifiedDateString]
            .first(where: {$0 != nil})?
            .flatMap { Date.ows_parseFromISO8601String($0) }
    }
}

// MARK: - To be moved
// Everything after this line should find a new home at some point

public extension OWSLinkPreviewManager {

    class func displayDomain(forUrl urlString: String?) -> String? {
        guard let urlString = urlString else {
            owsFailDebug("Missing url.")
            return nil
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url.")
            return nil
        }
        if StickerPackInfo.isStickerPackShare(url) {
            return stickerPackShareDomain(forUrl: url)
        }
        if GroupManager.isPossibleGroupInviteLink(url) {
            return "signal.org"
        }
        return url.host
    }

    private class func stickerPackShareDomain(forUrl url: URL) -> String? {
        guard let domain = url.host?.lowercased() else {
            return nil
        }
        guard url.path.count > 1 else {
            // Url must have non-empty path.
            return nil
        }
        return domain
    }
}

private func normalizeString(_ string: String, maxLines: Int) -> String {
    var result = string
    var components = result.components(separatedBy: .newlines)
    if components.count > maxLines {
        components = Array(components[0..<maxLines])
        result =  components.joined(separator: "\n")
    }
    let maxCharacterCount = 2048
    if result.count > maxCharacterCount {
        let endIndex = result.index(result.startIndex, offsetBy: maxCharacterCount)
        result = String(result[..<endIndex])
    }
    return result.filterStringForDisplay()
}
