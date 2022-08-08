// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import AFNetworking
import SignalCoreKit
import SessionUtilitiesKit

public struct LinkPreview: Codable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "linkPreview" }
    internal static let interactionForeignKey = ForeignKey(
        [Columns.url],
        to: [Interaction.Columns.linkPreviewUrl]
    )
    internal static let interactions = hasMany(Interaction.self, using: Interaction.linkPreviewForeignKey)
    public static let attachment = hasOne(Attachment.self, using: Attachment.linkPreviewForeignKey)
    
    /// We want to cache url previews to the nearest 100,000 seconds (~28 hours - simpler than 86,400) to ensure the user isn't shown a preview that is too stale
    internal static let timstampResolution: Double = 100000
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case url
        case timestamp
        case variant
        case title
        case attachmentId
    }
    
    public enum Variant: Int, Codable, Hashable, DatabaseValueConvertible {
        case standard
        case openGroupInvitation
    }
    
    /// The url for the link preview
    public let url: String
    
    /// The number of seconds since epoch rounded down to the nearest 100,000 seconds (~day) - This
    /// allows us to optimise against duplicate urls without having “stale” data last too long
    public let timestamp: TimeInterval
    
    /// The type of link preview
    public let variant: Variant
    
    /// The title for the link
    public let title: String?
    
    /// The id for the attachment for the link preview image
    public let attachmentId: String?
    
    // MARK: - Relationships
    
    public var attachment: QueryInterfaceRequest<Attachment> {
        request(for: LinkPreview.attachment)
    }
    
    // MARK: - Initialization
    
    public init(
        url: String,
        timestamp: TimeInterval = LinkPreview.timestampFor(
            sentTimestampMs: (Date().timeIntervalSince1970 * 1000)  // Default to now
        ),
        variant: Variant = .standard,
        title: String?,
        attachmentId: String? = nil
    ) {
        self.url = url
        self.timestamp = timestamp
        self.variant = variant
        self.title = title
        self.attachmentId = attachmentId
    }
}

// MARK: - Protobuf

public extension LinkPreview {
    init?(_ db: Database, proto: SNProtoDataMessage, body: String?, sentTimestampMs: TimeInterval) throws {
        guard let previewProto = proto.preview.first else { throw LinkPreviewError.noPreview }
        guard URL(string: previewProto.url) != nil else { throw LinkPreviewError.invalidInput }
        guard LinkPreview.isValidLinkUrl(previewProto.url) else { throw LinkPreviewError.invalidInput }
        
        // Try to get an existing link preview first
        let timestamp: TimeInterval = LinkPreview.timestampFor(sentTimestampMs: sentTimestampMs)
        let maybeLinkPreview: LinkPreview? = try? LinkPreview
            .filter(LinkPreview.Columns.url == previewProto.url)
            .filter(LinkPreview.Columns.timestamp == LinkPreview.timestampFor(
                sentTimestampMs: Double(proto.timestamp)
            ))
            .fetchOne(db)
        
        if let linkPreview: LinkPreview = maybeLinkPreview {
            self = linkPreview
            return
        }
        
        self.url = previewProto.url
        self.timestamp = timestamp
        self.variant = .standard
        self.title = LinkPreview.normalizeTitle(title: previewProto.title)
        
        if let imageProto = previewProto.image {
            let attachment: Attachment = Attachment(proto: imageProto)
            try attachment.insert(db)
            
            self.attachmentId = attachment.id
        }
        else {
            self.attachmentId = nil
        }
        
        // Make sure the quote is valid before completing
        guard self.title != nil || self.attachmentId != nil else { throw LinkPreviewError.invalidInput }
    }
}

// MARK: - Convenience

public extension LinkPreview {
    struct URLMatchResult {
        let urlString: String
        let matchRange: NSRange
    }
    
    static func timestampFor(sentTimestampMs: Double) -> TimeInterval {
        // We want to round the timestamp down to the nearest 100,000 seconds (~28 hours - simpler
        // than 86,400) to optimise LinkPreview storage without having too stale data
        return (floor(sentTimestampMs / 1000 / LinkPreview.timstampResolution) * LinkPreview.timstampResolution)
    }
    
    static func saveAttachmentIfPossible(_ db: Database, imageData: Data?, mimeType: String) throws -> String? {
        guard let imageData: Data = imageData, !imageData.isEmpty else { return nil }
        guard let fileExtension: String = MIMETypeUtil.fileExtension(forMIMEType: mimeType) else { return nil }
        
        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
        try imageData.write(to: NSURL.fileURL(withPath: filePath), options: .atomicWrite)
                
        guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true) else {
            return nil
        }
        
        return try Attachment(contentType: mimeType, dataSource: dataSource)?
            .inserted(db)
            .id
    }
    
    static func isValidLinkUrl(_ urlString: String) -> Bool {
        return URL(string: urlString) != nil
    }
    
    static func allPreviewUrls(forMessageBodyText body: String) -> [String] {
        return allPreviewUrlMatches(forMessageBodyText: body).map { $0.urlString }
    }
    
    // MARK: - Private Methods
    
    private static func allPreviewUrlMatches(forMessageBodyText body: String) -> [URLMatchResult] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        }
        catch {
            return []
        }

        var urlMatches: [URLMatchResult] = []
        let matches = detector.matches(in: body, options: [], range: NSRange(location: 0, length: body.count))
        for match in matches {
            guard let matchURL = match.url else { continue }
            
            // If the URL entered didn't have a scheme it will default to 'http', we want to catch this and
            // set the scheme to 'https' instead as we don't load previews for 'http' so this will result
            // in more previews actually getting loaded without forcing the user to enter 'https://' before
            // every URL they enter
            let urlString: String = (matchURL.absoluteString == "http://\(body)" ?
                "https://\(body)" :
                matchURL.absoluteString
            )
            
            if isValidLinkUrl(urlString) {
                let matchResult = URLMatchResult(urlString: urlString, matchRange: match.range)
                urlMatches.append(matchResult)
            }
        }
        
        return urlMatches
    }
    
    fileprivate static func normalizeTitle(title: String?) -> String? {
        guard var result: String = title, !result.isEmpty else { return nil }
        
        // Truncate title after 2 lines of text.
        let maxLineCount = 2
        var components = result.components(separatedBy: .newlines)
        
        if components.count > maxLineCount {
            components = Array(components[0..<maxLineCount])
            result =  components.joined(separator: "\n")
        }
        
        let maxCharacterCount = 2048
        if result.count > maxCharacterCount {
            let endIndex = result.index(result.startIndex, offsetBy: maxCharacterCount)
            result = String(result[..<endIndex])
        }
        
        return result.filterStringForDisplay()
    }
    
    // MARK: - Text Parsing

    private static var previewUrlCache: Atomic<NSCache<NSString, NSString>> = Atomic(NSCache())

    static func previewUrl(for body: String?, selectedRange: NSRange? = nil) -> String? {
        guard Storage.shared[.areLinkPreviewsEnabled] else { return nil }
        guard let body: String = body else { return nil }

        if let cachedUrl = previewUrlCache.wrappedValue.object(forKey: body as NSString) as String? {
            guard cachedUrl.count > 0 else {
                return nil
            }
            
            return cachedUrl
        }
        
        let previewUrlMatches: [URLMatchResult] = allPreviewUrlMatches(forMessageBodyText: body)
        
        guard let urlMatch: URLMatchResult = previewUrlMatches.first else {
            // Use empty string to indicate "no preview URL" in the cache.
            previewUrlCache.mutate { $0.setObject("", forKey: body as NSString) }
            return nil
        }

        if let selectedRange: NSRange = selectedRange {
            let cursorAtEndOfMatch: Bool = (
                (urlMatch.matchRange.location + urlMatch.matchRange.length) == selectedRange.location
            )
            
            if selectedRange.location != body.count, (urlMatch.matchRange.intersection(selectedRange) != nil || cursorAtEndOfMatch) {
                // we don't want to cache the result here, as we want to fetch the link preview
                // if the user moves the cursor.
                return nil
            }
        }

        previewUrlCache.mutate { $0.setObject(urlMatch.urlString as NSString, forKey: body as NSString) }
        
        return urlMatch.urlString
    }
}

// MARK: - Drafts

public extension LinkPreview {
    private struct Contents {
        public var title: String?
        public var imageUrl: String?

        public init(title: String?, imageUrl: String? = nil) {
            self.title = title
            self.imageUrl = imageUrl
        }
    }
    
    private static let serialQueue = DispatchQueue(label: "org.signal.linkPreview")
    
    // This cache should only be accessed on serialQueue.
    //
    // We should only maintain a "cache" of the last known draft.
    private static var linkPreviewDraftCache: LinkPreviewDraft?
    
    // Twitter doesn't return OpenGraph tags to Signal
    // `curl -A Signal "https://twitter.com/signalapp/status/1280166087577997312?s=20"`
    // If this ever changes, we can switch back to our default User-Agent
    private static let userAgentString = "WhatsApp"
    
    private static func cachedLinkPreview(forPreviewUrl previewUrl: String) -> LinkPreviewDraft? {
        return serialQueue.sync {
            guard let linkPreviewDraft = linkPreviewDraftCache,
                linkPreviewDraft.urlString == previewUrl else {
                return nil
            }
            return linkPreviewDraft
        }
    }
    
    private static func setCachedLinkPreview(_ linkPreviewDraft: LinkPreviewDraft, forPreviewUrl previewUrl: String) {
        assert(previewUrl == linkPreviewDraft.urlString)

        // Exit early if link previews are not enabled in order to avoid
        // tainting the cache.
        guard Storage.shared[.areLinkPreviewsEnabled] else { return }

        serialQueue.sync {
            linkPreviewDraftCache = linkPreviewDraft
        }
    }
    
    static func tryToBuildPreviewInfo(previewUrl: String?) -> Promise<LinkPreviewDraft> {
        guard Storage.shared[.areLinkPreviewsEnabled] else {
            return Promise(error: LinkPreviewError.featureDisabled)
        }
        guard let previewUrl: String = previewUrl else {
            return Promise(error: LinkPreviewError.invalidInput)
        }
        
        if let cachedInfo = cachedLinkPreview(forPreviewUrl: previewUrl) {
            return Promise.value(cachedInfo)
        }
        
        return downloadLink(url: previewUrl)
            .then(on: DispatchQueue.global()) { data, response -> Promise<LinkPreviewDraft> in
                return parseLinkDataAndBuildDraft(linkData: data, response: response, linkUrlString: previewUrl)
            }
            .then(on: DispatchQueue.global()) { linkPreviewDraft -> Promise<LinkPreviewDraft> in
                guard linkPreviewDraft.isValid() else { throw LinkPreviewError.noPreview }
                
                setCachedLinkPreview(linkPreviewDraft, forPreviewUrl: previewUrl)

                return Promise.value(linkPreviewDraft)
            }
    }

    private static func downloadLink(url urlString: String, remainingRetries: UInt = 3) -> Promise<(Data, URLResponse)> {
        Logger.verbose("url: \(urlString)")

        // let sessionConfiguration = ContentProxy.sessionConfiguration() // Loki: Signal's proxy appears to have been banned by YouTube
        let sessionConfiguration = URLSessionConfiguration.ephemeral

        // Don't use any caching to protect privacy of these requests.
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        
        // FIXME: Refactor to stop using AFHTTPRequest
        let sessionManager = AFHTTPSessionManager(baseURL: nil,
                                                  sessionConfiguration: sessionConfiguration)
        sessionManager.requestSerializer = AFHTTPRequestSerializer()
        sessionManager.responseSerializer = AFHTTPResponseSerializer()

        guard ContentProxy.configureSessionManager(sessionManager: sessionManager, forUrl: urlString) else {
            return Promise(error: LinkPreviewError.assertionFailure)
        }
        
        sessionManager.requestSerializer.setValue(self.userAgentString, forHTTPHeaderField: "User-Agent")

        let (promise, resolver) = Promise<(Data, URLResponse)>.pending()
        sessionManager.get(
            urlString,
            parameters: [String: AnyObject](),
            headers: nil,
            progress: nil,
            success: { task, value in
                guard let response = task.response as? HTTPURLResponse else {
                    resolver.reject(LinkPreviewError.assertionFailure)
                    return
                }
                if let contentType = response.allHeaderFields["Content-Type"] as? String {
                    guard contentType.lowercased().hasPrefix("text/") else {
                        resolver.reject(LinkPreviewError.invalidContent)
                        return
                    }
                }
                guard let data = value as? Data else {
                    resolver.reject(LinkPreviewError.assertionFailure)
                    return
                }
                guard data.count > 0 else {
                    resolver.reject(LinkPreviewError.invalidContent)
                    return
                }
                
                resolver.fulfill((data, response))
            },
            failure: { _, error in
                guard isRetryable(error: error) else {
                    resolver.reject(LinkPreviewError.couldNotDownload)
                    return
                }

                guard remainingRetries > 0 else {
                    resolver.reject(LinkPreviewError.couldNotDownload)
                    return
                }
                
                LinkPreview.downloadLink(
                    url: urlString,
                    remainingRetries: (remainingRetries - 1)
                )
                .done(on: DispatchQueue.global()) { (data, response) in
                    resolver.fulfill((data, response))
                }
                .catch(on: DispatchQueue.global()) { (error) in
                    resolver.reject(error)
                }
                .retainUntilComplete()
            }
        )
        
        return promise
    }
    
    private static func parseLinkDataAndBuildDraft(linkData: Data, response: URLResponse, linkUrlString: String) -> Promise<LinkPreviewDraft> {
        do {
            let contents = try parse(linkData: linkData, response: response)

            let title = contents.title
            guard let imageUrl = contents.imageUrl else {
                return Promise.value(LinkPreviewDraft(urlString: linkUrlString, title: title))
            }

            guard URL(string: imageUrl) != nil else {
                return Promise.value(LinkPreviewDraft(urlString: linkUrlString, title: title))
            }
            guard let imageFileExtension = fileExtension(forImageUrl: imageUrl) else {
                return Promise.value(LinkPreviewDraft(urlString: linkUrlString, title: title))
            }
            guard let imageMimeType = mimetype(forImageFileExtension: imageFileExtension) else {
                return Promise.value(LinkPreviewDraft(urlString: linkUrlString, title: title))
            }

            return downloadImage(url: imageUrl, imageMimeType: imageMimeType)
                .map(on: DispatchQueue.global()) { (imageData: Data) -> LinkPreviewDraft in
                    // We always recompress images to Jpeg
                    LinkPreviewDraft(urlString: linkUrlString, title: title, jpegImageData: imageData)
                }
                .recover(on: DispatchQueue.global()) { _ -> Promise<LinkPreviewDraft> in
                    Promise.value(LinkPreviewDraft(urlString: linkUrlString, title: title))
                }
        } catch {
            return Promise(error: error)
        }
    }
    
    private static func parse(linkData: Data, response: URLResponse) throws -> Contents {
        guard let linkText = String(data: linkData, urlResponse: response) else {
            print("Could not parse link text.")
            throw LinkPreviewError.invalidInput
        }
        
        let content = HTMLMetadata.construct(parsing: linkText)

        var title: String?
        let rawTitle = content.ogTitle ?? content.titleTag
        if
            let decodedTitle: String = decodeHTMLEntities(inString: rawTitle ?? ""),
            let normalizedTitle: String = LinkPreview.normalizeTitle(title: decodedTitle),
            normalizedTitle.count > 0
        {
            title = normalizedTitle
        }

        Logger.verbose("title: \(String(describing: title))")

        guard let rawImageUrlString = content.ogImageUrlString ?? content.faviconUrlString else {
            return Contents(title: title)
        }
        guard let imageUrlString = decodeHTMLEntities(inString: rawImageUrlString)?.ows_stripped() else {
            return Contents(title: title)
        }

        return Contents(title: title, imageUrl: imageUrlString)
    }
    
    private static func downloadImage(url urlString: String, imageMimeType: String) -> Promise<Data> {
        guard let url = URL(string: urlString) else { return Promise(error: LinkPreviewError.invalidInput) }
        guard let assetDescription = ProxiedContentAssetDescription(url: url as NSURL) else {
            return Promise(error: LinkPreviewError.invalidInput)
        }
        
        let (promise, resolver) = Promise<ProxiedContentAsset>.pending()
        DispatchQueue.main.async {
            _ = ProxiedContentDownloader.defaultDownloader.requestAsset(
                assetDescription: assetDescription,
                priority: .high,
                success: { _, asset in
                    resolver.fulfill(asset)
                },
                failure: { _ in
                    resolver.reject(LinkPreviewError.couldNotDownload)
                },
                shouldIgnoreSignalProxy: true
            )
        }
        
        return promise.then(on: DispatchQueue.global()) { (asset: ProxiedContentAsset) -> Promise<Data> in
            do {
                let imageSize = NSData.imageSize(forFilePath: asset.filePath, mimeType: imageMimeType)
                
                guard imageSize.width > 0, imageSize.height > 0 else {
                    return Promise(error: LinkPreviewError.invalidContent)
                }
                
                let data = try Data(contentsOf: URL(fileURLWithPath: asset.filePath))

                guard let srcImage = UIImage(data: data) else {
                    return Promise(error: LinkPreviewError.invalidContent)
                }
                
                // Loki: If it's a GIF then ensure its validity and don't download it as a JPG
                if (imageMimeType == OWSMimeTypeImageGif && NSData(data: data).ows_isValidImage(withMimeType: OWSMimeTypeImageGif)) { return Promise.value(data) }

                let maxImageSize: CGFloat = 1024
                let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
                
                guard shouldResize else {
                    guard let dstData = srcImage.jpegData(compressionQuality: 0.8) else {
                        return Promise(error: LinkPreviewError.invalidContent)
                    }
                    
                    return Promise.value(dstData)
                }

                guard let dstImage = srcImage.resized(withMaxDimensionPoints: maxImageSize) else {
                    return Promise(error: LinkPreviewError.invalidContent)
                }
                guard let dstData = dstImage.jpegData(compressionQuality: 0.8) else {
                    return Promise(error: LinkPreviewError.invalidContent)
                }
                
                return Promise.value(dstData)
            }
            catch {
                return Promise(error: LinkPreviewError.assertionFailure)
            }
        }
    }
    
    private static func isRetryable(error: Error) -> Bool {
        if (error as NSError).domain == kCFErrorDomainCFNetwork as String {
            // Network failures are retried.
            return true
        }
        
        return false
    }
    
    private static func fileExtension(forImageUrl urlString: String) -> String? {
        guard let imageUrl = URL(string: urlString) else { return nil }
        
        let imageFilename = imageUrl.lastPathComponent
        let imageFileExtension = (imageFilename as NSString).pathExtension.lowercased()
        
        guard imageFileExtension.count > 0 else {
            // TODO: For those links don't have a file extension, we should figure out a way to know the image mime type
            return "png"
        }
        
        return imageFileExtension
    }
    
    private static func mimetype(forImageFileExtension imageFileExtension: String) -> String? {
        guard imageFileExtension.count > 0 else { return nil }
        guard let imageMimeType = MIMETypeUtil.mimeType(forFileExtension: imageFileExtension) else { return nil }
        
        return imageMimeType
    }
    
    private static func decodeHTMLEntities(inString value: String) -> String? {
        guard let data = value.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        return attributedString.string
    }
}
