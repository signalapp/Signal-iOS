//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                    completion: @escaping (UIImage) -> Void)
    func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String?
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

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsFailDebug("Should not be called.")
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String? {
        owsFailDebug("Should not be called.")
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

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState() == .loaded)
        guard let imageData = linkPreviewDraft.imageData else {
            owsFailDebug("Missing imageData.")
            return
        }
        DispatchQueue.global().async {
            guard let image = UIImage(data: imageData) else {
                owsFailDebug("Could not load image: \(imageData.count)")
                return
            }
            completion(image)
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String? {
        guard let urlString = self.urlString() else {
            owsFailDebug("Missing urlString.")
            return nil
        }
        return "\(urlString).\(NSStringForAttachmentThumbnailQuality(thumbnailQuality))"
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil)

    @objc
    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState() == .loaded)
        guard let imageData = linkPreviewDraft.imageData else {
            owsFailDebug("Missing imageData.")
            return .zero
        }
        let imageMetadata = (imageData as NSData).imageMetadata(withPath: nil, mimeType: nil)
        guard imageMetadata.isValid else {
            owsFailDebug("Invalid image.")
            return .zero
        }
        let imagePixelSize = imageMetadata.pixelSize
        guard imagePixelSize.width > 0,
              imagePixelSize.height > 0 else {
            owsFailDebug("Invalid image size.")
            return .zero
        }
        let result = imagePixelSize
        imagePixelSizeCache.set(result)
        return result
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

    public let conversationStyle: ConversationStyle?

    @objc
    public required init(
        linkPreview: OWSLinkPreview,
        imageAttachment: TSAttachment?,
        conversationStyle: ConversationStyle?
    ) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        self.conversationStyle = conversationStyle
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

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState() == .loaded)
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            owsFailDebug("Could not load image.")
            return
        }
        DispatchQueue.global().async {
            guard attachmentStream.isImage,
                  attachmentStream.isValidImage else {
                return
            }
            guard attachmentStream.isValidVisualMedia else {
                owsFailDebug("Invalid image.")
                return
            }
            if attachmentStream.shouldBeRenderedByYY {
                guard let imageFilepath = attachmentStream.originalFilePath else {
                    owsFailDebug("Attachment is missing file path.")
                    return
                }
                guard let image = YYImage(contentsOfFile: imageFilepath) else {
                    owsFailDebug("Could not load image: \(imageFilepath)")
                    return
                }
                completion(image)
            } else {
                attachmentStream.thumbnailImage(quality: thumbnailQuality,
                                                success: { image in
                                                    completion(image)
                                                },
                                                failure: {
                                                    owsFailDebug("Could not load thumnail.")
                                                })
            }
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String? {
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return nil
        }
        return "\(attachmentStream.uniqueId).\(NSStringForAttachmentThumbnailQuality(thumbnailQuality))"
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil)

    @objc
    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState() == .loaded)
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return CGSize.zero
        }
        let result = attachmentStream.imageSizePixels
        imagePixelSizeCache.set(result)
        return result
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
