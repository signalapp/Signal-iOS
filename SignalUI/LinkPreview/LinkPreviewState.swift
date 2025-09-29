//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public enum LinkPreviewImageState: Equatable {
    case none
    case loading(blurHash: String?)
    case loaded
    case invalid
    case failed(blurHash: String?)
}

// MARK: -

public struct LinkPreviewImageCacheKey: Hashable, Equatable {
    public let id: Attachment.IDType?
    public let isBlurHash: Bool
    public let urlString: String?
    public let thumbnailQuality: AttachmentThumbnailQuality

    public init(
        id: Attachment.IDType?,
        urlString: String?,
        isBlurHash: Bool = false,
        thumbnailQuality: AttachmentThumbnailQuality
    ) {
        self.id = id
        self.urlString = urlString
        self.isBlurHash = isBlurHash
        self.thumbnailQuality = thumbnailQuality
    }
}

public protocol LinkPreviewState: AnyObject {
    var isLoaded: Bool { get }
    var urlString: String? { get }
    var displayDomain: String? { get }
    var title: String? { get }
    var imageState: LinkPreviewImageState { get }
    func imageAsync(
        thumbnailQuality: AttachmentThumbnailQuality,
        completion: @escaping (UIImage) -> Void
    )
    func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey?
    var imagePixelSize: CGSize { get }
    var previewDescription: String? { get }
    var date: Date? { get }
    var isGroupInviteLink: Bool { get }
    var activityIndicatorStyle: UIActivityIndicatorView.Style { get }
    var conversationStyle: ConversationStyle? { get }
}

// MARK: -

extension LinkPreviewState {
    var hasLoadedImageOrBlurHash: Bool {
        switch imageState {
        case .loaded:
            return isLoaded
        case let .loading(blurHash), let .failed(blurHash):
            return blurHash != nil
        default:
            return false
        }
    }

    var shouldShowInvalidImageIcon: Bool {
        switch imageState {
        case let .failed(blurHash):
            return blurHash != nil
        default:
            return false
        }
    }
}

// MARK: -

public enum LinkPreviewLinkType {
    case preview
    case incomingMessage
    case outgoingMessage
    case incomingMessageGroupInviteLink
    case outgoingMessageGroupInviteLink
}

// MARK: -

final public class LinkPreviewLoading: LinkPreviewState {

    public let linkType: LinkPreviewLinkType

    public init(linkType: LinkPreviewLinkType) {
        self.linkType = linkType
    }

    public var isLoaded: Bool { false }

    public var urlString: String? { nil }

    public var displayDomain: String? { return nil }

    public var title: String? { nil }

    public var imageState: LinkPreviewImageState { .none }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        owsFailDebug("Should not be called.")
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        owsFailDebug("Should not be called.")
        return nil
    }

    public var imagePixelSize: CGSize { .zero }

    public var previewDescription: String? { nil }

    public var date: Date? { nil }

    public var isGroupInviteLink: Bool {
        switch linkType {
        case .incomingMessageGroupInviteLink, .outgoingMessageGroupInviteLink:
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

final public class LinkPreviewDraft: LinkPreviewState {

    let linkPreviewDraft: OWSLinkPreviewDraft

    public init(linkPreviewDraft: OWSLinkPreviewDraft) {
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

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
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

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        guard let urlString = urlString else {
            owsFailDebug("Missing urlString.")
            return nil
        }
        return .init(id: nil, urlString: urlString, thumbnailQuality: thumbnailQuality)
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil, lock: .sharedGlobal)

    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState == .loaded)
        guard let imageData = linkPreviewDraft.imageData else {
            owsFailDebug("Missing imageData.")
            return .zero
        }
        let imageMetadata = imageData.imageMetadata(withPath: nil, mimeType: nil)
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

final public class LinkPreviewSent: LinkPreviewState {

    private let linkPreview: OWSLinkPreview
    private let imageAttachment: ReferencedAttachment?
    private let isFailedImageAttachmentDownload: Bool

    public let conversationStyle: ConversationStyle?

    public init(
        linkPreview: OWSLinkPreview,
        imageAttachment: ReferencedAttachment?,
        isFailedImageAttachmentDownload: Bool,
        conversationStyle: ConversationStyle?
    ) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        self.isFailedImageAttachmentDownload = isFailedImageAttachmentDownload
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
        guard let imageAttachment = imageAttachment else {
            return .none
        }
        guard let attachmentStream = imageAttachment.attachment.asStream() else {
            if let blurHash = imageAttachment.attachment.blurHash {
                if isFailedImageAttachmentDownload {
                    return .failed(blurHash: blurHash)
                } else {
                    return .loading(blurHash: blurHash)
                }
            } else {
                return .none
            }
        }
        switch attachmentStream.contentType {
        case .image, .animatedImage:
            break
        default:
            return .invalid
        }
        return .loaded
    }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        switch imageState {
        case .none, .invalid:
            owsFailDebug("Unexpected image state")
        case let .loading(blurHash), let .failed(blurHash):
            DispatchQueue.global().async {
                guard let blurHash else { return }
                guard let image = BlurHash.image(for: blurHash) else {
                    owsFailDebug("Could not load blurHash")
                    return
                }
                completion(image)
            }
        case .loaded:
            guard let attachmentStream = imageAttachment?.attachment.asStream() else {
                owsFailDebug("Could not load image.")
                return
            }
            DispatchQueue.global().async {
                switch attachmentStream.contentType {
                case .animatedImage:
                    guard let image = try? attachmentStream.decryptedSDAnimatedImage() else {
                        owsFailDebug("Could not load image")
                        return
                    }
                    completion(image)
                case .image:
                    Task {
                        guard let image = await attachmentStream.thumbnailImage(quality: thumbnailQuality) else {
                            owsFailDebug("Could not load thumnail.")
                            return
                        }
                        completion(image)
                    }
                default:
                    owsFailDebug("Invalid image.")
                    return
                }
            }
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        guard let imageAttachment else { return nil }
        guard let attachmentStream = imageAttachment.attachment.asStream() else {
            return .init(
                id: imageAttachment.attachment.id,
                urlString: nil,
                isBlurHash: true,
                thumbnailQuality: thumbnailQuality
            )
        }
        return .init(id: attachmentStream.id, urlString: nil, thumbnailQuality: thumbnailQuality)
    }

    public var imagePixelSize: CGSize {
        switch imageState {
        case .none, .invalid:
            owsFailDebug("Unexpected image state")
            return .zero
        case let .loading(blurHash), let .failed(blurHash):
            guard blurHash != nil else { return .zero }
            return imageAttachment?.reference.sourceMediaSizePixels
                // Fall back to default size to render the blurhash in.
                ?? CGSize(width: 400, height: 236)
        case .loaded:
            guard let attachmentStream = imageAttachment?.attachment.asStream() else {
                return CGSize.zero
            }

            switch attachmentStream.contentType {
            case .image(let pixelSize):
                return pixelSize
            case .animatedImage(let pixelSize):
                return pixelSize
            case .audio, .video, .file, .invalid:
                return .zero
            }
        }
    }

    public var previewDescription: String? { linkPreview.previewDescription }

    public var date: Date? { linkPreview.date }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}
