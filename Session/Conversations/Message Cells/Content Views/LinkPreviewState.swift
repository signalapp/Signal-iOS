// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

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

public class LinkPreviewSent: LinkPreviewState {
    private let linkPreview: LinkPreview
    private let imageAttachment: Attachment?

    public var imageSize: CGSize {
        guard let width: UInt = imageAttachment?.width, let height: UInt = imageAttachment?.height else {
            return CGSize.zero
        }
        
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    public required init(linkPreview: LinkPreview, imageAttachment: Attachment?) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
    }

    public func isLoaded() -> Bool {
        return true
    }
    
    public func urlString() -> String? {
        return linkPreview.url
    }

    public func displayDomain() -> String? {
        guard let displayDomain: String = URL(string: linkPreview.url)?.host else {
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
        guard linkPreview.attachmentId != nil else { return .none }
        guard let imageAttachment: Attachment = imageAttachment else {
            owsFailDebug("Missing imageAttachment.")
            return .none
        }
        
        switch imageAttachment.state {
            case .downloaded, .uploaded:
                guard imageAttachment.isImage && imageAttachment.isValid else {
                    return .invalid
                }
                
                return .loaded
                
            case .pending, .downloading, .uploading: return .loading
            case .failed: return .invalid
        }
    }

    public func image() -> UIImage? {
        // Note: We don't check if the image is valid here because that can be confirmed
        // in 'imageState' and it's a little inefficient
        guard imageAttachment?.isImage == true else { return nil }
        guard let imageData: Data = try? imageAttachment?.readDataFromFile() else {
            return nil
        }
        guard let image = UIImage(data: imageData) else {
            owsFailDebug("Could not load image: \(imageAttachment?.localRelativeFilePath ?? "unknown")")
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
