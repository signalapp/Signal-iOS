//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import YYImage

@objc
public enum LinkPreviewImageState: Int {
    case none
    case loading
    case loaded
    case invalid
}

// MARK: -

@objc
public protocol LinkPreviewState {
    func isLoaded() -> Bool
    func urlString() -> String?
    func displayDomain() -> String?
    func title() -> String?
    func imageState() -> LinkPreviewImageState
    func image() -> UIImage?
    var imagePixelSize: CGSize { get }
    func previewDescription() -> String?
    func date() -> Date?
    var isGroupInviteLink: Bool { get }
    var activityIndicatorStyle: UIActivityIndicatorView.Style { get }
    var conversationStyle: ConversationStyle? { get }
}

// MARK: -

extension LinkPreviewState {
    var hasLoadedImage: Bool {
        isLoaded() && imageState() == .loaded
    }
}

// MARK: -

@objc
public enum LinkPreviewLinkType: UInt {
    case preview
    case incomingMessage
    case outgoingMessage
    case incomingMessageGroupInviteLink
    case outgoingMessageGroupInviteLink
}

// MARK: -

@objc
public class LinkPreviewLoading: NSObject, LinkPreviewState {

    public let linkType: LinkPreviewLinkType

    @objc
    required init(linkType: LinkPreviewLinkType) {
        self.linkType = linkType
    }

    public func isLoaded() -> Bool {
        return false
    }

    public func urlString() -> String? {
        return nil
    }

    public func displayDomain() -> String? {
        return nil
    }

    public func title() -> String? {
        return nil
    }

    public func imageState() -> LinkPreviewImageState {
        return .none
    }

    public func image() -> UIImage? {
        return nil
    }

    public let imagePixelSize: CGSize = .zero

    public func previewDescription() -> String? {
        return nil
    }

    public func date() -> Date? {
        return nil
    }

    public var isGroupInviteLink: Bool {
        switch linkType {
        case .incomingMessageGroupInviteLink,
             .outgoingMessageGroupInviteLink:
            return true
        default:
            return false
        }
    }

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        switch linkType {
        case .incomingMessageGroupInviteLink:
            return .gray
        case .outgoingMessageGroupInviteLink:
            return .white
        default:
            return LinkPreviewView.defaultActivityIndicatorStyle
        }
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

@objc
public class LinkPreviewDraft: NSObject, LinkPreviewState {
    let linkPreviewDraft: OWSLinkPreviewDraft

    @objc
    public required init(linkPreviewDraft: OWSLinkPreviewDraft) {
        self.linkPreviewDraft = linkPreviewDraft
    }

    public func isLoaded() -> Bool {
        return true
    }

    public func urlString() -> String? {
        return linkPreviewDraft.urlString
    }

    public func displayDomain() -> String? {
        guard let displayDomain = linkPreviewDraft.displayDomain() else {
            owsFailDebug("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public func title() -> String? {
        guard let value = linkPreviewDraft.title,
            value.count > 0 else {
                return nil
        }
        return value
    }

    public func imageState() -> LinkPreviewImageState {
        if linkPreviewDraft.imageData != nil {
            return .loaded
        } else {
            return .none
        }
    }

    public func image() -> UIImage? {
        assert(imageState() == .loaded)

        guard let imageData = linkPreviewDraft.imageData else {
            return nil
        }
        guard let image = UIImage(data: imageData) else {
            owsFailDebug("Could not load image: \(imageData.count)")
            return nil
        }
        return image
    }

    public var imagePixelSize: CGSize {
        guard let image = self.image() else {
            return .zero
        }
        return image.pixelSize()
    }

    public func previewDescription() -> String? {
        linkPreviewDraft.previewDescription
    }

    public func date() -> Date? {
        linkPreviewDraft.date
    }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

@objc
public class LinkPreviewSent: NSObject, LinkPreviewState {
    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSAttachment?

    private let _conversationStyle: ConversationStyle
    public var conversationStyle: ConversationStyle? {
        _conversationStyle
    }

    @objc
    public required init(linkPreview: OWSLinkPreview,
                  imageAttachment: TSAttachment?,
                  conversationStyle: ConversationStyle) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        _conversationStyle = conversationStyle
    }

    public func isLoaded() -> Bool {
        return true
    }

    public func urlString() -> String? {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url")
            return nil
        }
        return urlString
    }

    public func displayDomain() -> String? {
        guard let displayDomain = linkPreview.displayDomain() else {
            Logger.error("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public func title() -> String? {
        guard let value = linkPreview.title?.filterForDisplay,
            value.count > 0 else {
                return nil
        }
        return value
    }

    public func imageState() -> LinkPreviewImageState {
        guard linkPreview.imageAttachmentId != nil else {
            return .none
        }
        guard let imageAttachment = imageAttachment else {
            Logger.warn("Missing imageAttachment.")
            return .none
        }
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return .loading
        }
        guard attachmentStream.isImage,
            attachmentStream.isValidImage else {
            return .invalid
        }
        return .loaded
    }

    public func image() -> UIImage? {
        assert(imageState() == .loaded)

        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            owsFailDebug("Could not load image.")
            return nil
        }
        guard attachmentStream.isImage,
            attachmentStream.isValidImage else {
            return nil
        }
        guard let imageFilepath = attachmentStream.originalFilePath else {
            owsFailDebug("Attachment is missing file path.")
            return nil
        }

        guard NSData.ows_isValidImage(atPath: imageFilepath, mimeType: attachmentStream.contentType) else {
            owsFailDebug("Invalid image.")
            return nil
        }

        let imageClass: UIImage.Type
        if attachmentStream.contentType == OWSMimeTypeImageWebp {
            imageClass = YYImage.self
        } else {
            imageClass = UIImage.self
        }

        guard let image = imageClass.init(contentsOfFile: imageFilepath) else {
            owsFailDebug("Could not load image: \(imageFilepath)")
            return nil
        }

        return image
    }

    @objc
    public var imagePixelSize: CGSize {
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return CGSize.zero
        }
        return attachmentStream.imageSize()
    }

    public func previewDescription() -> String? {
        linkPreview.previewDescription
    }

    public func date() -> Date? {
        linkPreview.date
    }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}
