//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import YYImage

public enum LinkPreviewImageState: Int {
    case none
    case loading
    case loaded
    case invalid
}

// MARK: -

public protocol LinkPreviewState: AnyObject {
    var isLoaded: Bool { get }
    var urlString: String? { get }
    var displayDomain: String? { get }
    var title: String? { get }
    var imageState: LinkPreviewImageState { get }
    func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                    completion: @escaping (UIImage) -> Void)
    func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String?
    var imagePixelSize: CGSize { get }
    var previewDescription: String? { get }
    var date: Date? { get }
    var isGroupInviteLink: Bool { get }
    var activityIndicatorStyle: UIActivityIndicatorView.Style { get }
    var conversationStyle: ConversationStyle? { get }
}

// MARK: -

extension LinkPreviewState {
    var hasLoadedImage: Bool {
        isLoaded && imageState == .loaded
    }
}

// MARK: -

public enum LinkPreviewLinkType: UInt {
    case preview
    case incomingMessage
    case outgoingMessage
    case incomingMessageGroupInviteLink
    case outgoingMessageGroupInviteLink
}

// MARK: -

public class LinkPreviewLoading: LinkPreviewState {

    public let linkType: LinkPreviewLinkType

    public required init(linkType: LinkPreviewLinkType) {
        self.linkType = linkType
    }

    public var isLoaded: Bool { false }

    public var urlString: String? { nil }

    public var displayDomain: String? { return nil }

    public var title: String? { nil }

    public var imageState: LinkPreviewImageState { .none }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsFailDebug("Should not be called.")
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String? {
        owsFailDebug("Should not be called.")
        return nil
    }

    public var imagePixelSize: CGSize { .zero }

    public var previewDescription: String? { nil }

    public var date: Date? { nil }

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
            return .medium
        case .outgoingMessageGroupInviteLink:
            return .medium
        default:
            return LinkPreviewView.defaultActivityIndicatorStyle
        }
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

public class LinkPreviewDraft: LinkPreviewState {

    let linkPreviewDraft: OWSLinkPreviewDraft

    public required init(linkPreviewDraft: OWSLinkPreviewDraft) {
        self.linkPreviewDraft = linkPreviewDraft
    }

    public var isLoaded: Bool { true }

    public var urlString: String? { linkPreviewDraft.urlString }

    public var displayDomain: String? {
        guard let displayDomain = linkPreviewDraft.displayDomain else {
            owsFailDebug("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public var title: String? { linkPreviewDraft.title?.nilIfEmpty }

    public var imageState: LinkPreviewImageState { linkPreviewDraft.imageData != nil ? .loaded : .none }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState == .loaded)
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
        guard let urlString = urlString else {
            owsFailDebug("Missing urlString.")
            return nil
        }
        return "\(urlString).\(NSStringForAttachmentThumbnailQuality(thumbnailQuality))"
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil)

    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState == .loaded)
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

    public var previewDescription: String? { linkPreviewDraft.previewDescription }

    public var date: Date? { linkPreviewDraft.date }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

public class LinkPreviewSent: LinkPreviewState {

    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSAttachment?

    public let conversationStyle: ConversationStyle?

    public required init(
        linkPreview: OWSLinkPreview,
        imageAttachment: TSAttachment?,
        conversationStyle: ConversationStyle?
    ) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        self.conversationStyle = conversationStyle
    }

    public var isLoaded: Bool { true }

    public var urlString: String? {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url")
            return nil
        }
        return urlString
    }

    public var displayDomain: String? {
        guard let displayDomain = linkPreview.displayDomain else {
            Logger.error("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public var title: String? { linkPreview.title?.filterForDisplay.nilIfEmpty }

    public var imageState: LinkPreviewImageState {
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
        guard attachmentStream.isImageMimeType,
            attachmentStream.isValidImage else {
            return .invalid
        }
        return .loaded
    }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState == .loaded)
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            owsFailDebug("Could not load image.")
            return
        }
        DispatchQueue.global().async {
            guard attachmentStream.isImageMimeType,
                  attachmentStream.isValidImage else {
                return
            }
            guard attachmentStream.isValidVisualMedia else {
                owsFailDebug("Invalid image.")
                return
            }
            if attachmentStream.isAnimatedContent {
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

    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState == .loaded)
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return CGSize.zero
        }
        let result = attachmentStream.imageSizePixels
        imagePixelSizeCache.set(result)
        return result
    }

    public var previewDescription: String? { linkPreview.previewDescription }

    public var date: Date? { linkPreview.date }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}
