// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

protocol LinkPreviewState {
    var isLoaded: Bool { get }
    var urlString: String? { get }
    var title: String? { get }
    var imageState: LinkPreview.ImageState { get }
    var image: UIImage? { get }
}

public extension LinkPreview {
    enum ImageState: Int {
        case none
        case loading
        case loaded
        case invalid
    }
    
    // MARK: LoadingState
    
    struct LoadingState: LinkPreviewState {
        var isLoaded: Bool { false }
        var urlString: String? { nil }
        var title: String? { nil }
        var imageState: LinkPreview.ImageState { .none }
        var image: UIImage? { nil }
    }
    
    // MARK: DraftState
    
    struct DraftState: LinkPreviewState {
        var isLoaded: Bool { true }
        var urlString: String? { linkPreviewDraft.urlString }

        var title: String? {
            guard let value = linkPreviewDraft.title, value.count > 0 else { return nil }
            
            return value
        }
        
        var imageState: LinkPreview.ImageState {
            if linkPreviewDraft.jpegImageData != nil { return .loaded }
            
            return .none
        }
        
        var image: UIImage? {
            guard let jpegImageData = linkPreviewDraft.jpegImageData else { return nil }
            guard let image = UIImage(data: jpegImageData) else {
                owsFailDebug("Could not load image: \(jpegImageData.count)")
                return nil
            }
            
            return image
        }
        
        // MARK: - Type Specific
        
        private let linkPreviewDraft: LinkPreviewDraft
        
        // MARK: - Initialization

        init(linkPreviewDraft: LinkPreviewDraft) {
            self.linkPreviewDraft = linkPreviewDraft
        }
    }
    
    // MARK: SentState
    
    struct SentState: LinkPreviewState {
        var isLoaded: Bool { true }
        var urlString: String? { linkPreview.url }

        var title: String? {
            guard let value = linkPreview.title, value.count > 0 else { return nil }
            
            return value
        }

        var imageState: LinkPreview.ImageState {
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
                    
                case .pendingDownload, .downloading, .uploading: return .loading
                case .failedDownload, .failedUpload, .invalid: return .invalid
            }
        }

        var image: UIImage? {
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
        
        // MARK: - Type Specific
        
        private let linkPreview: LinkPreview
        private let imageAttachment: Attachment?

        public var imageSize: CGSize {
            guard let width: UInt = imageAttachment?.width, let height: UInt = imageAttachment?.height else {
                return CGSize.zero
            }
            
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        
        // MARK: - Initialization

        init(linkPreview: LinkPreview, imageAttachment: Attachment?) {
            self.linkPreview = linkPreview
            self.imageAttachment = imageAttachment
        }
    }
}
