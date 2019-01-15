//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum LinkPreviewError: Int, Error {
    case invalidInput
    case assertionFailure
    case noPreview
}

@objc(OWSLinkPreview)
public class OWSLinkPreview: MTLModel {
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

        // TODO: Verify that url host is in whitelist.

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

        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageAttachmentId != nil
        if !hasTitle && !hasImage {
            Logger.error("Preview has neither title nor image.")
            throw LinkPreviewError.invalidInput
        }

        return OWSLinkPreview(urlString: urlString, title: title, imageAttachmentId: imageAttachmentId)
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

    private static let linkDomainWhitelist = [
    "youtube.com",
    "reddit.com",
    "imgur.com",
    "instagram.com"
    ]

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

    // MARK: - Text Parsing

    @objc
    public class func previewUrl(forMessageBodyText body: String?) -> String? {
        guard let body = body else {
            return nil
        }
        let components = body.components(separatedBy: .whitespacesAndNewlines)
        for component in components {
            if isValidLinkUrl(component) {
                return component
            }
        }
        return nil
    }
}
