//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum LinkPreviewError: Int, Error {
    case invalidInput
    case noPreview
}

// MARK: - OWSLinkPreviewDraft

// This contains the info for a link preview "draft".
public class OWSLinkPreviewDraft: NSObject {
    @objc
    public var urlString: String

    @objc
    public var title: String?

    @objc
    public var imageFilePath: String?

    public init(urlString: String, title: String?, imageFilePath: String? = nil) {
        self.urlString = urlString
        self.title = title
        self.imageFilePath = imageFilePath

        super.init()
    }

    deinit {
        // Eagerly clean up temp files.
        if let imageFilePath = imageFilePath {
            DispatchQueue.global().async {
                OWSFileSystem.deleteFile(imageFilePath)
            }
        }
    }

    fileprivate func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageFilePath != nil
        return hasTitle || hasImage
    }

    @objc
    public func displayDomain() -> String? {
        return OWSLinkPreview.displayDomain(forUrl: urlString)
    }
}

// MARK: - OWSLinkPreview

@objc
public class OWSLinkPreview: MTLModel {
    @objc
    public static let featureEnabled = true

    @objc
    public var urlString: String?

    @objc
    public var title: String?

    @objc
    public var imageAttachmentId: String?

    @objc
    public init(urlString: String, title: String?, imageAttachmentId: String?) {
        self.urlString = urlString
        self.title = title
        self.imageAttachmentId = imageAttachmentId

        super.init()
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
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
    public class func buildValidatedLinkPreview(dataMessage: SSKProtoDataMessage,
                                                body: String?,
                                                transaction: YapDatabaseReadWriteTransaction) throws -> OWSLinkPreview {
        guard OWSLinkPreview.featureEnabled else {
            throw LinkPreviewError.noPreview
        }
        guard let previewProto = dataMessage.preview.first else {
            throw LinkPreviewError.noPreview
        }
        guard dataMessage.attachments.count < 1 else {
            Logger.error("Discarding link preview; message has attachments.")
            throw LinkPreviewError.invalidInput
        }
        let urlString = stripPossibleLinkUrl(previewProto.url)

        guard URL(string: urlString) != nil else {
            Logger.error("Could not parse preview URL.")
            throw LinkPreviewError.invalidInput
        }

        guard let body = body else {
            Logger.error("Preview for message without body.")
            throw LinkPreviewError.invalidInput
        }
        let bodyComponents = body.components(separatedBy: .whitespacesAndNewlines)
        guard bodyComponents.contains(urlString) else {
            Logger.error("URL not present in body.")
            throw LinkPreviewError.invalidInput
        }

        guard isValidLinkUrl(urlString) else {
            Logger.verbose("Invalid link URL \(urlString).")
            Logger.error("Invalid link URL.")
            throw LinkPreviewError.invalidInput
        }

        var title: String?
        if let rawTitle = previewProto.title {
            let normalizedTitle = OWSLinkPreview.normalizeTitle(title: rawTitle)
            if normalizedTitle.count > 0 {
                title = normalizedTitle
            }
        }

        var imageAttachmentId: String?
        if let imageProto = previewProto.image {
            if let imageAttachmentPointer = TSAttachmentPointer(fromProto: imageProto, albumMessage: nil) {
                imageAttachmentPointer.save(with: transaction)
                imageAttachmentId = imageAttachmentPointer.uniqueId
            } else {
                Logger.error("Could not parse image proto.")
                throw LinkPreviewError.invalidInput
            }
        }

        let linkPreview = OWSLinkPreview(urlString: urlString, title: title, imageAttachmentId: imageAttachmentId)

        guard linkPreview.isValid() else {
            owsFailDebug("Preview has neither title nor image.")
            throw LinkPreviewError.invalidInput
        }

        return linkPreview
    }

    @objc
    public class func buildValidatedLinkPreview(fromInfo info: OWSLinkPreviewDraft,
                                                transaction: YapDatabaseReadWriteTransaction) throws -> OWSLinkPreview {
        guard OWSLinkPreview.featureEnabled else {
            throw LinkPreviewError.noPreview
        }
        guard SSKPreferences.areLinkPreviewsEnabled() else {
            throw LinkPreviewError.noPreview
        }
        let imageAttachmentId = OWSLinkPreview.saveAttachmentIfPossible(inputFilePath: info.imageFilePath,
                                                                        transaction: transaction)

        let linkPreview = OWSLinkPreview(urlString: info.urlString, title: info.title, imageAttachmentId: imageAttachmentId)

        guard linkPreview.isValid() else {
            owsFailDebug("Preview has neither title nor image.")
            throw LinkPreviewError.invalidInput
        }

        return linkPreview
    }

    private class func saveAttachmentIfPossible(inputFilePath filePath: String?,
                                                transaction: YapDatabaseReadWriteTransaction) -> String? {
        guard let filePath = filePath else {
            return nil
        }
        guard let fileSize = OWSFileSystem.fileSize(ofPath: filePath) else {
            owsFailDebug("Unknown file size for path: \(filePath)")
            return nil
        }
        guard fileSize.uint32Value > 0 else {
            owsFailDebug("Invalid file size for path: \(filePath)")
            return nil
        }
        let filename = (filePath as NSString).lastPathComponent
        let fileExtension = (filename as NSString).pathExtension
        guard fileExtension.count > 0 else {
            owsFailDebug("Invalid file extension for path: \(filePath)")
            return nil
        }
        guard let contentType = MIMETypeUtil.mimeType(forFileExtension: fileExtension) else {
            owsFailDebug("Invalid content type for path: \(filePath)")
            return nil
        }
        guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true) else {
            owsFailDebug("Could not create data source for path: \(filePath)")
            return nil
        }
        let attachment = TSAttachmentStream(contentType: contentType, byteCount: fileSize.uint32Value, sourceFilename: nil, caption: nil, albumMessageId: nil)
        guard attachment.write(dataSource) else {
            owsFailDebug("Could not write data source for path: \(filePath)")
            return nil
        }
        attachment.save(with: transaction)

        return attachment.uniqueId
    }

    private func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageAttachmentId != nil
        return hasTitle || hasImage
    }

    @objc
    public func removeAttachment(transaction: YapDatabaseReadWriteTransaction) {
        guard let imageAttachmentId = imageAttachmentId else {
            owsFailDebug("No attachment id.")
            return
        }
        guard let attachment = TSAttachment.fetch(uniqueId: imageAttachmentId, transaction: transaction) else {
            owsFailDebug("Could not load attachment.")
            return
        }
        attachment.remove(with: transaction)
    }

    private class func normalizeTitle(title: String) -> String {
        var result = title
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

    // MARK: - Domain Whitelist

    // TODO: Finalize
    private static let linkDomainWhitelist = [
        "youtube.com",
        "reddit.com",
        "imgur.com",
        "instagram.com",
        "giphy.com",
        "youtu.be"
    ]

    // TODO: Finalize
    private static let mediaDomainWhitelist = [
        "ytimg.com",
        "cdninstagram.com",
        "redd.it"
    ]

    private static let protocolWhitelist = [
        "https"
    ]

    @objc
    public func displayDomain() -> String? {
        return OWSLinkPreview.displayDomain(forUrl: urlString)
    }

    @objc
    public class func displayDomain(forUrl urlString: String?) -> String? {
        guard let urlString = urlString else {
            owsFailDebug("Missing url.")
            return nil
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url.")
            return nil
        }
        guard url.path.count > 0 else {
            owsFailDebug("Invalid url (empty path).")
            return nil
        }
        guard let result = whitelistedDomain(forUrl: url,
                                             domainWhitelist: OWSLinkPreview.linkDomainWhitelist) else {
                                                owsFailDebug("Missing domain.")
                                                return nil
        }
        return result
    }

    private class func stripPossibleLinkUrl(_ urlString: String) -> String {
        var result = urlString.ows_stripped()
        let suffixToStrip = ","
        while result.hasSuffix(suffixToStrip) {
            let endIndex = result.index(result.endIndex, offsetBy: -suffixToStrip.count)
            result = String(result[..<endIndex]).ows_stripped()
        }
        return result
    }

    @objc
    public class func isValidLinkUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        return whitelistedDomain(forUrl: url,
                                 domainWhitelist: OWSLinkPreview.linkDomainWhitelist) != nil
    }

    @objc
    public class func isValidMediaUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        return whitelistedDomain(forUrl: url,
                                 domainWhitelist: OWSLinkPreview.linkDomainWhitelist + OWSLinkPreview.mediaDomainWhitelist) != nil
    }

    private class func whitelistedDomain(forUrl url: URL, domainWhitelist: [String]) -> String? {
        guard let urlProtocol = url.scheme?.lowercased() else {
            return nil
        }
        guard protocolWhitelist.contains(urlProtocol) else {
            return nil
        }
        guard let domain = url.host?.lowercased() else {
            return nil
        }
        // TODO: We need to verify:
        //
        // * The final domain whitelist.
        // * The relationship between the "link" whitelist and the "media" whitelist.
        // * Exact match or suffix-based?
        // * Case-insensitive?
        // * Protocol?
        for whitelistedDomain in domainWhitelist {
            if domain == whitelistedDomain.lowercased() ||
                domain.hasSuffix("." + whitelistedDomain.lowercased()) {
                return whitelistedDomain
            }
        }
        return nil
    }

    // MARK: - Serial Queue

    private static let serialQueue = DispatchQueue(label: "org.signal.linkPreview")

    private class func assertIsOnSerialQueue() {
        if _isDebugAssertConfiguration(), #available(iOS 10.0, *) {
            assertOnQueue(serialQueue)
        }
    }

    // MARK: - Text Parsing

    // This cache should only be accessed on main thread.
    private static var previewUrlCache: NSCache<AnyObject, AnyObject> = NSCache()

    @objc
    public class func previewUrl(forMessageBodyText body: String?) -> String? {
        AssertIsOnMainThread()

        guard OWSLinkPreview.featureEnabled else {
            return nil
        }
        guard SSKPreferences.areLinkPreviewsEnabled() else {
            return nil
        }
        guard let body = body else {
            return nil
        }
        if let cachedUrl = previewUrlCache.object(forKey: body as AnyObject) as? String {
            Logger.verbose("URL parsing cache hit.")
            guard cachedUrl.count > 0 else {
                return nil
            }
            return cachedUrl
        }
        let components = body.components(separatedBy: .whitespacesAndNewlines)
        for component in components {
            let urlString = stripPossibleLinkUrl(component)
            if isValidLinkUrl(urlString) {
                previewUrlCache.setObject(urlString as AnyObject, forKey: body as AnyObject)
                return urlString
            }
        }
        // Use empty string to indicate "no preview URL" in the cache.
        previewUrlCache.setObject("" as AnyObject, forKey: body as AnyObject)
        return nil
    }

    // MARK: - Preview Construction

    // This cache should only be accessed on serialQueue.
    private static var linkPreviewDraftCache: NSCache<AnyObject, OWSLinkPreviewDraft> = NSCache()

    // Completion will always be invoked exactly once.
    //
    // The completion is called with a link preview if one can be built for
    // the message body.  It building the preview fails, completion will be
    // called with nil to avoid failing the message send.
    @objc
    public class func tryToBuildPreviewInfo(previewUrl: String?,
                                            callbackQueue: DispatchQueue,
                                            completion completionParam: @escaping (OWSLinkPreviewDraft?) -> Void) {

        // Ensure we invoke completion on the callback queue.
        let completion = { (linkPreviewDraft) in
            callbackQueue.async {
                completionParam(linkPreviewDraft)
            }
        }

        guard OWSLinkPreview.featureEnabled else {
            completion(nil)
            return
        }
        guard SSKPreferences.areLinkPreviewsEnabled() else {
            completion(nil)
            return
        }
        guard let previewUrl = previewUrl else {
            completion(nil)
            return
        }
        serialQueue.async {
            if let cachedInfo = linkPreviewDraftCache.object(forKey: previewUrl as AnyObject) {
                Logger.verbose("Link preview info cache hit.")
                completion(cachedInfo)
                return
            }
            downloadLink(url: previewUrl, completion: { (data) in
                DispatchQueue.global().async {
                    guard let data = data else {
                        completion(nil)
                        return
                    }
                    parse(linkData: data, linkUrlString: previewUrl) { (linkPreviewDraft) in
                        guard let linkPreviewDraft = linkPreviewDraft else {
                            completion(nil)
                            return
                        }
                        guard linkPreviewDraft.isValid() else {
                            completion(nil)
                            return
                        }
                        serialQueue.async {
                            previewUrlCache.setObject(linkPreviewDraft, forKey: previewUrl as AnyObject)

                            completion(linkPreviewDraft)
                        }
                    }
                }
            })
        }
    }

    private class func downloadLink(url: String,
                                    completion: @escaping (Data?) -> Void,
                                    remainingRetries: UInt = 3) {

        Logger.verbose("url: \(url)")

        let sessionConfiguration = ContentProxy.sessionConfiguration()

        // Don't use any caching to protect privacy of these requests.
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil

        let sessionManager = AFHTTPSessionManager(baseURL: nil,
                                                  sessionConfiguration: sessionConfiguration)
        sessionManager.requestSerializer = AFHTTPRequestSerializer()
        sessionManager.responseSerializer = AFHTTPResponseSerializer()

        // Remove all headers from the request.
        for headerField in sessionManager.requestSerializer.httpRequestHeaders.keys {
            sessionManager.requestSerializer.setValue(nil, forHTTPHeaderField: headerField)
        }

        sessionManager.get(url,
                           parameters: [String: AnyObject](),
                           progress: nil,
                           success: { _, value in

                            guard let data = value as? Data else {
                                Logger.warn("Result is not data: \(type(of: value)).")
                                completion(nil)
                                return
                            }
                            completion(data)
        },
                           failure: { _, error in
                            Logger.verbose("Error: \(error)")

                            guard isRetryable(error: error) else {
                                Logger.warn("Error is not retryable.")
                                completion(nil)
                                return
                            }

                            guard remainingRetries > 0 else {
                                Logger.warn("No more retries.")
                                completion(nil)
                                return
                            }
                            OWSLinkPreview.downloadLink(url: url, completion: completion, remainingRetries: remainingRetries - 1)
        })
    }

    private class func downloadImage(url urlString: String,
                                     completion: @escaping (Data?) -> Void) {

        Logger.verbose("url: \(urlString)")

        guard let url = URL(string: urlString) else {
            Logger.error("Could not parse URL.")
            return completion(nil)
        }

        guard let assetDescription = ProxiedContentAssetDescription(url: url as NSURL) else {
            Logger.error("Could not create asset description.")
            return completion(nil)
        }
        DispatchQueue.main.async {
            _ = ProxiedContentDownloader.defaultDownloader.requestAsset(assetDescription: assetDescription,
                                                                        priority: .high,
                                                                        success: { (_, asset) in
                                                                            DispatchQueue.global().async {
                                                                                do {
                                                                                    let data = try Data(contentsOf: URL(fileURLWithPath: asset.filePath))
                                                                                    completion(data)
                                                                                } catch {
                                                                                    owsFailDebug("Could not load asset data: \(type(of: asset.filePath)).")
                                                                                    completion(nil)
                                                                                }
                                                                            }

            }, failure: { (_) in
                DispatchQueue.global().async {
                    Logger.verbose("Error downloading asset")

                    completion(nil)
                }
            })
        }
    }

    private class func isRetryable(error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == kCFErrorDomainCFNetwork as String {
            // Network failures are retried.
            return true
        }
        return false
    }

    // Example:
    //
    //    <meta property="og:title" content="Randomness is Random - Numberphile">
    //    <meta property="og:image" content="https://i.ytimg.com/vi/tP-Ipsat90c/maxresdefault.jpg">
    private class func parse(linkData: Data,
                             linkUrlString: String,
                             completion: @escaping (OWSLinkPreviewDraft?) -> Void) {
        guard let linkText = String(bytes: linkData, encoding: .utf8) else {
            owsFailDebug("Could not parse link text.")
            completion(nil)
            return
        }

        var title: String?
        if let rawTitle = NSRegularExpression.parseFirstMatch(pattern: "<meta\\s+property\\s*=\\s*\"og:title\"\\s+content\\s*=\\s*\"(.*?)\"\\s*/?>", text: linkText) {
            if let decodedTitle = decodeHTMLEntities(inString: rawTitle) {
                let normalizedTitle = OWSLinkPreview.normalizeTitle(title: decodedTitle)
                if normalizedTitle.count > 0 {
                    title = normalizedTitle
                }
            }
        }

        Logger.verbose("title: \(String(describing: title))")

        guard let rawImageUrlString = NSRegularExpression.parseFirstMatch(pattern: "<meta\\s+property\\s*=\\s*\"og:image\"\\s+content\\s*=\\s*\"(.*?)\"\\s*/?>", text: linkText) else {
            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
        }
        guard let imageUrlString = decodeHTMLEntities(inString: rawImageUrlString)?.ows_stripped() else {
            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
        }
        guard isValidMediaUrl(imageUrlString) else {
            Logger.error("Invalid image URL.")
            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
        }
        Logger.verbose("imageUrlString: \(imageUrlString)")
        guard let imageUrl = URL(string: imageUrlString) else {
            Logger.error("Could not parse image URL.")
            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
        }
        let imageFilename = imageUrl.lastPathComponent
        let imageFileExtension = (imageFilename as NSString).pathExtension.lowercased()
        guard let imageMimeType = MIMETypeUtil.mimeType(forFileExtension: imageFileExtension) else {
            Logger.error("Image URL has unknown content type: \(imageFileExtension).")
            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
        }
        let kValidMimeTypes = [
            OWSMimeTypeImagePng,
            OWSMimeTypeImageJpeg
        ]
        guard kValidMimeTypes.contains(imageMimeType) else {
            Logger.error("Image URL has invalid content type: \(imageMimeType).")
            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
        }

        downloadImage(url: imageUrlString,
                      completion: { (imageData) in
                        guard let imageData = imageData else {
                            Logger.error("Could not download image.")
                            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
                        }
                        let imageFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: imageFileExtension)
                        do {
                            try imageData.write(to: NSURL.fileURL(withPath: imageFilePath), options: .atomicWrite)
                        } catch let error as NSError {
                            owsFailDebug("file write failed: \(imageFilePath), \(error)")
                            return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
                        }
                        // NOTE: imageSize(forFilePath:...) will call ows_isValidImage(...).
                        let imageSize = NSData.imageSize(forFilePath: imageFilePath, mimeType: imageMimeType)
                        let kMaxImageSize: CGFloat = 2048
                        guard imageSize.width > 0,
                            imageSize.height > 0,
                            imageSize.width < kMaxImageSize,
                            imageSize.height < kMaxImageSize else {
                                Logger.error("Image has invalid size: \(imageSize).")
                                return completion(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
                        }

                        let linkPreviewDraft = OWSLinkPreviewDraft(urlString: linkUrlString, title: title, imageFilePath: imageFilePath)
                        completion(linkPreviewDraft)
        })
    }

    private class func decodeHTMLEntities(inString value: String) -> String? {
        guard let data = value.data(using: .utf8) else {
            return nil
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html,
            NSAttributedString.DocumentReadingOptionKey.characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        return attributedString.string
    }
}
