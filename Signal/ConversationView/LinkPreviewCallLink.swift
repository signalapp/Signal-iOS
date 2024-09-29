//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

// MARK: -

public class LinkPreviewCallLink: LinkPreviewState {
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

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}

public class CommonCallLinksUI {
    public static func callLinkIcon() -> UIImage? {
        guard let image = UIImage(named: "video-compact") else { return nil }
        let newSize = CGSize(square: Constants.circleViewDimension)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let finalImage = renderer.image { context in
            let rect = CGRect(origin: .zero, size: newSize)
            let circlePath = UIBezierPath(ovalIn: rect)

            Constants.iconBackgroundColor.setFill()
            circlePath.fill()

            context.cgContext.addPath(circlePath.cgPath)
            context.cgContext.clip()

            Constants.iconTintColor.set()
            let centerOffset = Constants.circleViewDimension/2 - Constants.iconDimension/2
            let imageRect = CGRect(
                x: centerOffset,
                y: centerOffset,
                width: Constants.iconDimension,
                height: Constants.iconDimension
            )
            image.withRenderingMode(.alwaysTemplate).draw(in: imageRect)
        }

        return finalImage
    }

    public enum Constants {
        public static let circleViewDimension: CGFloat = 64
        fileprivate static let iconDimension: CGFloat = 36
        fileprivate static let iconBackgroundColor = UIColor(rgbHex: 0xE4E4FD)
        fileprivate static let iconTintColor = UIColor(rgbHex: 0x5151F6)
    }
}
