//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import AFNetworking
import Foundation
import PromiseKit

@objc
public enum LinkPreviewError: Int, Error {
    case invalidInput
    case noPreview
    case assertionFailure
    case couldNotDownload
    case featureDisabled
    case invalidContent
    case invalidMediaContent
    case attachmentFailedToSave
}

// MARK: - OWSLinkPreviewDraft

public class OWSLinkPreviewContents: NSObject {
    @objc
    public var title: String?

    @objc
    public var imageUrl: String?

    public init(title: String?, imageUrl: String? = nil) {
        self.title = title
        self.imageUrl = imageUrl

        super.init()
    }
}

// This contains the info for a link preview "draft".
public class OWSLinkPreviewDraft: NSObject {
    @objc
    public var urlString: String

    @objc
    public var title: String?

    @objc
    public var jpegImageData: Data?

    public init(urlString: String, title: String?, jpegImageData: Data? = nil) {
        self.urlString = urlString
        self.title = title
        self.jpegImageData = jpegImageData

        super.init()
    }

    fileprivate func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = jpegImageData != nil
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
    
    // Whether this preview can be rendered as an attachment
    @objc
    public var isDirectAttachment: Bool = false

    @objc
    public init(urlString: String, title: String?, imageAttachmentId: String?, isDirectAttachment: Bool = false) {
        self.urlString = urlString
        self.title = title
        self.imageAttachmentId = imageAttachmentId
        self.isDirectAttachment = isDirectAttachment

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
    public class func isInvalidContentError(_ error: Error) -> Bool {
        guard let error = error as? LinkPreviewError else { return false }
        return error == .invalidContent
    }

    @objc
    public class func buildValidatedLinkPreview(dataMessage: SNProtoDataMessage,
                                                body: String?,
                                                transaction: YapDatabaseReadWriteTransaction) throws -> OWSLinkPreview {
        guard OWSLinkPreview.featureEnabled else {
            throw LinkPreviewError.noPreview
        }
        guard let previewProto = dataMessage.preview.first else {
            throw LinkPreviewError.noPreview
        }
        guard dataMessage.attachments.count < 1 else {
            throw LinkPreviewError.invalidInput
        }
        let urlString = previewProto.url

        guard URL(string: urlString) != nil else {
            throw LinkPreviewError.invalidInput
        }

        guard let body = body else {
            throw LinkPreviewError.invalidInput
        }
        let previewUrls = allPreviewUrls(forMessageBodyText: body)
        guard previewUrls.contains(urlString) else {
            throw LinkPreviewError.invalidInput
        }

        guard isValidLinkUrl(urlString) else {
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
                throw LinkPreviewError.invalidInput
            }
        }

        let linkPreview = OWSLinkPreview(urlString: urlString, title: title, imageAttachmentId: imageAttachmentId)

        guard linkPreview.isValid() else {
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
        guard SSKPreferences.areLinkPreviewsEnabled else {
            throw LinkPreviewError.noPreview
        }
        let imageAttachmentId = OWSLinkPreview.saveAttachmentIfPossible(jpegImageData: info.jpegImageData,
                                                                        transaction: transaction)

        let linkPreview = OWSLinkPreview(urlString: info.urlString, title: info.title, imageAttachmentId: imageAttachmentId)

        guard linkPreview.isValid() else {
            throw LinkPreviewError.invalidInput
        }

        return linkPreview
    }
    
    private class func saveAttachmentIfPossible(jpegImageData: Data?,
                                                transaction: YapDatabaseReadWriteTransaction) -> String? {
        return saveAttachmentIfPossible(imageData: jpegImageData, mimeType: OWSMimeTypeImageJpeg, transaction: transaction);
    }
    
    private class func saveAttachmentIfPossible(imageData: Data?, mimeType: String, transaction: YapDatabaseReadWriteTransaction) -> String? {
        guard let imageData = imageData else { return nil }
        
        let fileSize = imageData.count
        guard fileSize > 0 else {
            return nil
        }
        
        guard let fileExtension = fileExtension(forMimeType: mimeType) else { return nil }
        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
        do {
            try imageData.write(to: NSURL.fileURL(withPath: filePath), options: .atomicWrite)
        } catch {
            return nil
        }
        
        guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true) else {
            return nil
        }
        let attachment = TSAttachmentStream(contentType: mimeType, byteCount: UInt32(fileSize), sourceFilename: nil, caption: nil, albumMessageId: nil)
        guard attachment.write(dataSource) else {
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
            return
        }
        guard let attachment = TSAttachment.fetch(uniqueId: imageAttachmentId, transaction: transaction) else {
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

    @objc
    public func displayDomain() -> String? {
        return OWSLinkPreview.displayDomain(forUrl: urlString)
    }

    @objc
    public class func displayDomain(forUrl urlString: String?) -> String? {
        guard let urlString = urlString else {
            return nil
        }
        guard let url = URL(string: urlString) else {
            return nil
        }
        return url.host
    }

    @objc
    public class func isValidLinkUrl(_ urlString: String) -> Bool {
        return URL(string: urlString) != nil
    }

    @objc
    public class func isValidMediaUrl(_ urlString: String) -> Bool {
        return URL(string: urlString) != nil
    }

    // MARK: - Serial Queue

    private static let serialQueue = DispatchQueue(label: "org.signal.linkPreview")

    // MARK: - Text Parsing

    // This cache should only be accessed on main thread.
    private static var previewUrlCache: NSCache<NSString, NSString> = NSCache()

    @objc
    public class func previewUrl(forRawBodyText body: String?, selectedRange: NSRange) -> String? {
        return previewUrl(forMessageBodyText: body, selectedRange: selectedRange)
    }

    @objc
    public class func previewURL(forRawBodyText body: String?) -> String? {
        return previewUrl(forMessageBodyText: body, selectedRange: nil)
    }

    public class func previewUrl(forMessageBodyText body: String?, selectedRange: NSRange?) -> String? {

        // Exit early if link previews are not enabled in order to avoid
        // tainting the cache.
        guard OWSLinkPreview.featureEnabled else {
            return nil
        }

        guard SSKPreferences.areLinkPreviewsEnabled else {
            return nil
        }

        guard let body = body else {
            return nil
        }

        if let cachedUrl = previewUrlCache.object(forKey: body as NSString) as String? {
            guard cachedUrl.count > 0 else {
                return nil
            }
            return cachedUrl
        }
        let previewUrlMatches = allPreviewUrlMatches(forMessageBodyText: body)
        guard let urlMatch = previewUrlMatches.first else {
            // Use empty string to indicate "no preview URL" in the cache.
            previewUrlCache.setObject("", forKey: body as NSString)
            return nil
        }

        if let selectedRange = selectedRange {
            let cursorAtEndOfMatch = urlMatch.matchRange.location + urlMatch.matchRange.length == selectedRange.location
            if selectedRange.location != body.count,
                (urlMatch.matchRange.intersection(selectedRange) != nil || cursorAtEndOfMatch) {
                // we don't want to cache the result here, as we want to fetch the link preview
                // if the user moves the cursor.
                return nil
            }
        }

        previewUrlCache.setObject(urlMatch.urlString as NSString, forKey: body as NSString)
        return urlMatch.urlString
    }

    struct URLMatchResult {
        let urlString: String
        let matchRange: NSRange
    }

    public class func allPreviewUrls(forMessageBodyText body: String) -> [String] {
        return allPreviewUrlMatches(forMessageBodyText: body).map { $0.urlString }
    }

    class func allPreviewUrlMatches(forMessageBodyText body: String) -> [URLMatchResult] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
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

    // MARK: - Preview Construction

    // This cache should only be accessed on serialQueue.
    //
    // We should only maintain a "cache" of the last known draft.
    private static var linkPreviewDraftCache: OWSLinkPreviewDraft?

    private class func cachedLinkPreview(forPreviewUrl previewUrl: String) -> OWSLinkPreviewDraft? {
        return serialQueue.sync {
            guard let linkPreviewDraft = linkPreviewDraftCache,
                linkPreviewDraft.urlString == previewUrl else {
                return nil
            }
            return linkPreviewDraft
        }
    }

    private class func setCachedLinkPreview(_ linkPreviewDraft: OWSLinkPreviewDraft,
                                            forPreviewUrl previewUrl: String) {
        assert(previewUrl == linkPreviewDraft.urlString)

        // Exit early if link previews are not enabled in order to avoid
        // tainting the cache.
        guard OWSLinkPreview.featureEnabled else {
            return
        }
        guard SSKPreferences.areLinkPreviewsEnabled else {
            return
        }

        serialQueue.sync {
            linkPreviewDraftCache = linkPreviewDraft
        }
    }

    @objc
    public class func tryToBuildPreviewInfoObjc(previewUrl: String?) -> AnyPromise {
        return AnyPromise(tryToBuildPreviewInfo(previewUrl: previewUrl))
    }

    public class func tryToBuildPreviewInfo(previewUrl: String?) -> Promise<OWSLinkPreviewDraft> {
        guard OWSLinkPreview.featureEnabled else {
            return Promise(error: LinkPreviewError.featureDisabled)
        }
        guard SSKPreferences.areLinkPreviewsEnabled else {
            return Promise(error: LinkPreviewError.featureDisabled)
        }
        guard let previewUrl = previewUrl else {
            return Promise(error: LinkPreviewError.invalidInput)
        }
        if let cachedInfo = cachedLinkPreview(forPreviewUrl: previewUrl) {
            return Promise.value(cachedInfo)
        }
        return downloadLink(url: previewUrl)
            .then(on: DispatchQueue.global()) { (data, response) -> Promise<OWSLinkPreviewDraft> in
                return parseLinkDataAndBuildDraft(linkData: data, response: response, linkUrlString: previewUrl)
            }.then(on: DispatchQueue.global()) { (linkPreviewDraft) -> Promise<OWSLinkPreviewDraft> in
                guard linkPreviewDraft.isValid() else {
                    throw LinkPreviewError.noPreview
                }
                setCachedLinkPreview(linkPreviewDraft, forPreviewUrl: previewUrl)

                return Promise.value(linkPreviewDraft)
        }
    }
    
    // Twitter doesn't return OpenGraph tags to Signal
    // `curl -A Signal "https://twitter.com/signalapp/status/1280166087577997312?s=20"`
    // If this ever changes, we can switch back to our default User-Agent
    private static let userAgentString = "WhatsApp"

    class func downloadLink(url urlString: String,
                            remainingRetries: UInt = 3) -> Promise<(Data, URLResponse)> {

        Logger.verbose("url: \(urlString)")

        // let sessionConfiguration = ContentProxy.sessionConfiguration() // Loki: Signal's proxy appears to have been banned by YouTube
        let sessionConfiguration = URLSessionConfiguration.ephemeral

        // Don't use any caching to protect privacy of these requests.
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil

        let sessionManager = AFHTTPSessionManager(baseURL: nil,
                                                  sessionConfiguration: sessionConfiguration)
        sessionManager.requestSerializer = AFHTTPRequestSerializer()
        sessionManager.responseSerializer = AFHTTPResponseSerializer()

        guard ContentProxy.configureSessionManager(sessionManager: sessionManager, forUrl: urlString) else {
            return Promise(error: LinkPreviewError.assertionFailure)
        }
        
        sessionManager.requestSerializer.setValue(self.userAgentString, forHTTPHeaderField: "User-Agent")

        let (promise, resolver) = Promise<(Data, URLResponse)>.pending()
        sessionManager.get(urlString,
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
                            OWSLinkPreview.downloadLink(url: urlString, remainingRetries: remainingRetries - 1)
                            .done(on: DispatchQueue.global()) { (data, response) in
                                resolver.fulfill((data, response))
                            }.catch(on: DispatchQueue.global()) { (error) in
                                resolver.reject(error)
                            }.retainUntilComplete()
        })
        return promise
    }

    private class func downloadImage(url urlString: String, imageMimeType: String) -> Promise<Data> {
        guard let url = URL(string: urlString) else {
            return Promise(error: LinkPreviewError.invalidInput)
        }

        guard let assetDescription = ProxiedContentAssetDescription(url: url as NSURL) else {
            return Promise(error: LinkPreviewError.invalidInput)
        }
        let (promise, resolver) = Promise<ProxiedContentAsset>.pending()
        DispatchQueue.main.async {
            _ = ProxiedContentDownloader.defaultDownloader.requestAsset(assetDescription: assetDescription,
                                                                        priority: .high,
                                                                        success: { (_, asset) in
                                                                            resolver.fulfill(asset)
            }, failure: { (_) in
                resolver.reject(LinkPreviewError.couldNotDownload)
            }, shouldIgnoreSignalProxy: true)
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
            } catch {
                return Promise(error: LinkPreviewError.assertionFailure)
            }
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

    class func parseLinkDataAndBuildDraft(linkData: Data,
                                          response: URLResponse,
                                          linkUrlString: String) -> Promise<OWSLinkPreviewDraft> {
        do {
            let contents = try parse(linkData: linkData, response: response)

            let title = contents.title
            guard let imageUrl = contents.imageUrl else {
                return Promise.value(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
            }

            guard isValidMediaUrl(imageUrl) else {
                return Promise.value(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
            }
            guard let imageFileExtension = fileExtension(forImageUrl: imageUrl) else {
                return Promise.value(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
            }
            guard let imageMimeType = mimetype(forImageFileExtension: imageFileExtension) else {
                return Promise.value(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
            }

            return downloadImage(url: imageUrl, imageMimeType: imageMimeType)
                .map(on: DispatchQueue.global()) { (imageData: Data) -> OWSLinkPreviewDraft in
                    // We always recompress images to Jpeg.
                    let linkPreviewDraft = OWSLinkPreviewDraft(urlString: linkUrlString, title: title, jpegImageData: imageData)
                    return linkPreviewDraft
                }
                .recover(on: DispatchQueue.global()) { (_) -> Promise<OWSLinkPreviewDraft> in
                    return Promise.value(OWSLinkPreviewDraft(urlString: linkUrlString, title: title))
            }
        } catch {
            return Promise(error: error)
        }
    }

    class func parse(linkData: Data, response: URLResponse) throws -> OWSLinkPreviewContents {
        guard let linkText = String(data: linkData, urlResponse: response) else {
            print("Could not parse link text.")
            throw LinkPreviewError.invalidInput
        }
        
        let content = HTMLMetadata.construct(parsing: linkText)

        var title: String?
        let rawTitle = content.ogTitle ?? content.titleTag
        if let decodedTitle = decodeHTMLEntities(inString: rawTitle ?? "") {
            let normalizedTitle = OWSLinkPreview.normalizeTitle(title: decodedTitle)
            if normalizedTitle.count > 0 {
                title = normalizedTitle
            }
        }

        Logger.verbose("title: \(String(describing: title))")

        guard let rawImageUrlString = content.ogImageUrlString ?? content.faviconUrlString else {
            return OWSLinkPreviewContents(title: title)
        }
        guard let imageUrlString = decodeHTMLEntities(inString: rawImageUrlString)?.ows_stripped() else {
            return OWSLinkPreviewContents(title: title)
        }

        return OWSLinkPreviewContents(title: title, imageUrl: imageUrlString)
    }

    class func fileExtension(forImageUrl urlString: String) -> String? {
        guard let imageUrl = URL(string: urlString) else {
            return nil
        }
        let imageFilename = imageUrl.lastPathComponent
        let imageFileExtension = (imageFilename as NSString).pathExtension.lowercased()
        guard imageFileExtension.count > 0 else {
            // TODO: For those links don't have a file extension, we should figure out a way to know the image mime type
            return "png"
        }
        return imageFileExtension
    }
    
    class func fileExtension(forMimeType mimeType: String) -> String? {
        switch mimeType {
        case OWSMimeTypeImageGif: return "gif"
        case OWSMimeTypeImagePng: return "png"
        case OWSMimeTypeImageJpeg: return "jpg"
        default: return nil
        }
    }

    class func mimetype(forImageFileExtension imageFileExtension: String) -> String? {
        guard imageFileExtension.count > 0 else {
            return nil
        }
        guard let imageMimeType = MIMETypeUtil.mimeType(forFileExtension: imageFileExtension) else {
            return nil
        }
        return imageMimeType
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
