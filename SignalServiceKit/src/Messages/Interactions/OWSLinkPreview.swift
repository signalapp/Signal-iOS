//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum LinkPreviewError: Int, Error {
    case invalidInput
    case noPreview
}

// MARK: - OWSLinkPreviewInfo

// This contains the info for a link preview "draft".
public class OWSLinkPreviewInfo: NSObject {
    @objc
    public var urlString: String

    @objc
    public var title: String?

    @objc
    public var imageFilePath: String?

    @objc
    public init(urlString: String, title: String?, imageFilePath: String? = nil) {
        self.urlString = urlString
        self.title = title
        self.imageFilePath = imageFilePath

        super.init()
    }

    fileprivate func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageFilePath != nil
        return hasTitle || hasImage
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
        guard let previewProto = dataMessage.preview else {
            throw LinkPreviewError.noPreview
        }
        let urlString = previewProto.url

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

        let title: String? = previewProto.title?.trimmingCharacters(in: .whitespacesAndNewlines)

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
    public class func buildValidatedLinkPreview(fromInfo info: OWSLinkPreviewInfo,
                                                transaction: YapDatabaseReadWriteTransaction) throws -> OWSLinkPreview {
        guard OWSLinkPreview.featureEnabled else {
            throw LinkPreviewError.noPreview
        }
        let imageAttachmentId = OWSLinkPreview.saveAttachmentIfPossible(forFilePath: info.imageFilePath,
                                                                        transaction: transaction)

        let linkPreview = OWSLinkPreview(urlString: info.urlString, title: info.title, imageAttachmentId: imageAttachmentId)

        guard linkPreview.isValid() else {
            owsFailDebug("Preview has neither title nor image.")
            throw LinkPreviewError.invalidInput
        }

        return linkPreview
    }

    private class func saveAttachmentIfPossible(forFilePath filePath: String?,
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
        let attachment = TSAttachmentStream(contentType: contentType, byteCount: fileSize.uint32Value, sourceFilename: nil, caption: nil, albumMessageId: nil)
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

    // MARK: - Domain Whitelist

    // TODO: Finalize
    private static let linkDomainWhitelist = [
        "youtube.com",
        "reddit.com",
        "imgur.com",
        "instagram.com",
        "giphy.com",
        "instagram.com"
    ]

    // TODO: Finalize
    private static let mediaDomainWhitelist = [
        "ytimg.com",
        "cdninstagram.com"
    ]

    private static let protocolWhitelist = [
        "https"
    ]

    @objc
    public class func isValidLinkUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        return isUrlInDomainWhitelist(url: url,
                                      domainWhitelist: OWSLinkPreview.linkDomainWhitelist)
    }

    @objc
    public class func isValidMediaUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        return isUrlInDomainWhitelist(url: url,
                                      domainWhitelist: OWSLinkPreview.linkDomainWhitelist + OWSLinkPreview.mediaDomainWhitelist)
    }

    private class func isUrlInDomainWhitelist(url: URL, domainWhitelist: [String]) -> Bool {
        guard let urlProtocol = url.scheme?.lowercased() else {
            return false
        }
        guard protocolWhitelist.contains(urlProtocol) else {
            return false
        }
        guard let domain = url.host?.lowercased() else {
            return false
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
                return true
            }
        }
        return false
    }

    // MARK: - Serial Queue

    private static let serialQueue = DispatchQueue(label: "org.signal.linkPreview")

    private class func assertIsOnSerialQueue() {
        if _isDebugAssertConfiguration(), #available(iOS 10.0, *) {
            assertOnQueue(serialQueue)
        }
    }

    // MARK: - Text Parsing

    // This cache should only be accessed on serialQueue.
    private static var previewUrlCache: NSCache<AnyObject, AnyObject> = NSCache()

    private class func previewUrl(forMessageBodyText body: String?) -> String? {
        assertIsOnSerialQueue()

        guard OWSLinkPreview.featureEnabled else {
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
            if isValidLinkUrl(component) {
                previewUrlCache.setObject(component as AnyObject, forKey: body as AnyObject)
                return component
            }
        }
        return nil
    }

    // MARK: - Preview Construction

    // This cache should only be accessed on serialQueue.
    private static var linkPreviewInfoCache: NSCache<AnyObject, OWSLinkPreviewInfo> = NSCache()

    // Completion will always be invoked exactly once.
    //
    // The completion is called with a link preview if one can be built for
    // the message body.  It building the preview fails, completion will be
    // called with nil to avoid failing the message send.
    //
    // NOTE: Completion might be invoked on any thread.
    @objc
    public class func tryToBuildPreviewInfo(forMessageBodyText body: String?,
                                            completion: @escaping (OWSLinkPreviewInfo?) -> Void) {
        guard OWSLinkPreview.featureEnabled else {
            completion(nil)
            return
        }
        guard let body = body else {
            completion(nil)
            return
        }
        serialQueue.async {
            guard let previewUrl = previewUrl(forMessageBodyText: body) else {
                completion(nil)
                return
            }

            if let cachedInfo = linkPreviewInfoCache.object(forKey: previewUrl as AnyObject) {
                Logger.verbose("Link preview info cache hit.")
                completion(cachedInfo)
                return
            }
            downloadContents(ofUrl: previewUrl, completion: { (data) in
                DispatchQueue.global().async {
                    guard let data = data else {
                        completion(nil)
                        return
                    }
                    parse(linkData: data, linkUrlString: previewUrl) { (linkPreviewInfo) in
                        guard let linkPreviewInfo = linkPreviewInfo else {
                            completion(nil)
                            return
                        }
                        guard linkPreviewInfo.isValid() else {
                            completion(nil)
                            return
                        }
                        serialQueue.async {
                            previewUrlCache.setObject(linkPreviewInfo, forKey: previewUrl as AnyObject)

                            DispatchQueue.global().async {
                                completion(linkPreviewInfo)
                            }
                        }
                    }
                }
            })
        }
    }

    private class func downloadContents(ofUrl url: String,
                                        completion: @escaping (Data?) -> Void,
                                        remainingRetries: UInt = 3) {

        Logger.verbose("url: \(url)")

        guard let sessionManager: AFHTTPSessionManager = ReverseProxy.sessionManager(baseUrl: nil) else {
            owsFailDebug("Couldn't create session manager.")
            completion(nil)
            return
        }
        sessionManager.requestSerializer = AFHTTPRequestSerializer()
        sessionManager.responseSerializer = AFHTTPResponseSerializer()

        // Remove all headers from the request.
        for headerField in sessionManager.requestSerializer.httpRequestHeaders.keys {
            sessionManager.requestSerializer.setValue(nil, forHTTPHeaderField: headerField)
        }

        sessionManager.get(url,
                           parameters: {},
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
                            OWSLinkPreview.downloadContents(ofUrl: url, completion: completion, remainingRetries: remainingRetries - 1)
        })

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
                             completion: @escaping (OWSLinkPreviewInfo?) -> Void) {
        guard let linkText = String(bytes: linkData, encoding: .utf8) else {
            owsFailDebug("Could not parse link text.")
            completion(nil)
            return
        }
        Logger.verbose("linkText: \(linkText)")

        let title = parseFirstMatch(pattern: "<meta property=\"og:title\" content=\"([^\"]+)\">", text: linkText)
        Logger.verbose("title: \(String(describing: title))")

        guard let imageUrlString = parseFirstMatch(pattern: "<meta property=\"og:image\" content=\"([^\"]+)\">", text: linkText) else {
            return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
        }
        Logger.verbose("imageUrlString: \(imageUrlString)")
        guard let imageUrl = URL(string: imageUrlString) else {
            Logger.error("Could not parse image URL.")
            return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
        }
        let imageFilename = imageUrl.lastPathComponent
        let imageFileExtension = (imageFilename as NSString).pathExtension.lowercased()
        guard let imageMimeType = MIMETypeUtil.mimeType(forFileExtension: imageFileExtension) else {
            Logger.error("Image URL has unknown content type: \(imageFileExtension).")
            return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
        }
        let kValidMimeTypes = [
            OWSMimeTypeImagePng,
            OWSMimeTypeImageJpeg
            ]
        guard kValidMimeTypes.contains(imageMimeType) else {
            Logger.error("Image URL has invalid content type: \(imageMimeType).")
            return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
        }

        downloadContents(ofUrl: imageUrlString,
                         completion: { (imageData) in
                            guard let imageData = imageData else {
                                Logger.error("Could not download image.")
                                return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
                            }
                            let imageFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: imageFileExtension)
                            do {
                                try imageData.write(to: NSURL.fileURL(withPath: imageFilePath), options: .atomicWrite)
                            } catch let error as NSError {
                                owsFailDebug("file write failed: \(imageFilePath), \(error)")
                                return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
                            }
                            // NOTE: imageSize(forFilePath:...) will call ows_isValidImage(...).
                            let imageSize = NSData.imageSize(forFilePath: imageFilePath, mimeType: imageMimeType)
                            let kMaxImageSize: CGFloat = 2048
                            guard imageSize.width > 0,
                                imageSize.height > 0,
                                imageSize.width < kMaxImageSize,
                                imageSize.height < kMaxImageSize else {
                                    Logger.error("Image has invalid size: \(imageSize).")
                                    return completion(OWSLinkPreviewInfo(urlString: linkUrlString, title: title))
                            }

                            let linkPreviewInfo = OWSLinkPreviewInfo(urlString: linkUrlString, title: title, imageFilePath: imageFilePath)
                            completion(linkPreviewInfo)
        })
    }

    private class func parseFirstMatch(pattern: String,
                                       text: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: text,
                                                      options: [],
                                                      range: NSRange(location: 0, length: text.count)) else {
                                                        return nil
            }
            let matchRange = match.range(at: 1)
            guard let textRange = Range(matchRange, in: text) else {
                owsFailDebug("Invalid match.")
                return nil
            }
            let substring = String(text[textRange])
            return substring
        } catch {
            Logger.error("Error: \(error)")
            return nil
        }
    }
}
