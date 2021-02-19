//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

extension CGPoint {
    
    public func offsetBy(dx: CGFloat) -> CGPoint {
        return CGPoint(x: x + dx, y: y)
    }

    public func offsetBy(dy: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: y + dy)
    }
}

// MARK: -

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
}

// MARK: -

@objc
public class LinkPreviewLoading: NSObject, LinkPreviewState {

    override init() {
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
}

// MARK: -

@objc
public class LinkPreviewDraft: NSObject, LinkPreviewState {
    private let linkPreviewDraft: OWSLinkPreviewDraft

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
        if linkPreviewDraft.jpegImageData != nil {
            return .loaded
        } else {
            return .none
        }
    }

    public func image() -> UIImage? {
        guard let jpegImageData = linkPreviewDraft.jpegImageData else {
            return nil
        }
        guard let image = UIImage(data: jpegImageData) else {
            owsFailDebug("Could not load image: \(jpegImageData.count)")
            return nil
        }
        return image
    }
}

// MARK: -

@objc
public class LinkPreviewSent: NSObject, LinkPreviewState {
    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSAttachment?

    @objc
    public var imageSize: CGSize {
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return CGSize.zero
        }
        return attachmentStream.imageSize()
    }

    @objc
    public required init(linkPreview: OWSLinkPreview,
                  imageAttachment: TSAttachment?) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
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
        guard let value = linkPreview.title,
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
            owsFailDebug("Missing imageAttachment.")
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
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
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
        guard let image = UIImage(contentsOfFile: imageFilepath) else {
            owsFailDebug("Could not load image: \(imageFilepath)")
            return nil
        }
        return image
    }
}

// MARK: -

@objc
public protocol LinkPreviewViewDraftDelegate {
    func linkPreviewCanCancel() -> Bool
    func linkPreviewDidCancel()
}
