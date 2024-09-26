//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: -

class LinkPreviewCallLink: LinkPreviewState {
    private let linkPreview: OWSLinkPreview

    public let conversationStyle: ConversationStyle?

    public init(
        linkPreview: OWSLinkPreview,
        conversationStyle: ConversationStyle?
    ) {
        self.linkPreview = linkPreview
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

    public var title: String? {
        linkPreview.title?.filterForDisplay.nilIfEmpty ?? CallStrings.signalCall
    }

    public var imageState: LinkPreviewImageState {
        // Image is a local asset.
        return .loaded
    }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        if let image = CommonCallLinksUI.callLinkIcon() {
            completion(image)
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? { return nil }

    public var imagePixelSize: CGSize {
        return CGSize(square: CommonCallLinksUI.Constants.circleViewDimension)
    }

    public var previewDescription: String? {
        return linkPreview.previewDescription?.filterForDisplay.nilIfEmpty ?? CallStrings.callLinkDescription
    }

    public var date: Date? { linkPreview.date }

    public let isGroupInviteLink = false
    public var isCallLink = true

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}
