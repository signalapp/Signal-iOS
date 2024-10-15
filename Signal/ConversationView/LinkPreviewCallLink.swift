//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalRingRTC
public import SignalServiceKit

// MARK: -

public class LinkPreviewCallLink: LinkPreviewState {
    public let conversationStyle: ConversationStyle?

    public enum PreviewType {
        case sent(OWSLinkPreview, ConversationStyle)
        case draft(OWSLinkPreviewDraft)
    }

    private let previewType: PreviewType
    private let callLink: CallLink

    public init(previewType: PreviewType, callLink: CallLink) {
        self.previewType = previewType
        self.callLink = callLink
        switch previewType {
        case .sent(_, let conversationStyle):
            self.conversationStyle = conversationStyle
        case .draft:
            self.conversationStyle = nil
        }
    }

    public var isLoaded: Bool { true }

    public var urlString: String? {
        switch previewType {
        case .sent(let linkPreview, _):
            guard let urlString = linkPreview.urlString else {
                owsFailDebug("Missing url")
                return nil
            }
            return urlString
        case .draft(let linkPreviewDraft):
            return linkPreviewDraft.urlString
        }
    }

    public var displayDomain: String? {
        let displayDomain: String?
        switch previewType {
        case .sent(let linkPreview, _):
            displayDomain = linkPreview.displayDomain
        case .draft(let linkPreviewDraft):
            displayDomain = linkPreviewDraft.displayDomain
        }

        guard let displayDomain else {
            Logger.error("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public var title: String? {
        let title: String?
        switch previewType {
        case .sent(let linkPreview, _):
            title = linkPreview.title
        case .draft(let linkPreviewDraft):
            title = linkPreviewDraft.title
        }
        return title?.filterForDisplay.nilIfEmpty ?? CallStrings.signalCall
    }

    public var imageState: LinkPreviewImageState {
        // Image is a local asset.
        return .loaded
    }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        if let image = CommonCallLinksUI.callLinkIcon(rootKey: callLink.rootKey) {
            completion(image)
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? { return nil }

    public var imagePixelSize: CGSize {
        return CGSize(square: CommonCallLinksUI.Constants.circleViewDimension)
    }

    public var previewDescription: String? {
        let description: String?
        switch previewType {
        case .sent(let linkPreview, _):
            description = linkPreview.previewDescription
        case .draft(let linkPreviewDraft):
            description = linkPreviewDraft.previewDescription
        }
        return description?.filterForDisplay.nilIfEmpty ?? CallStrings.callLinkDescription
    }

    public var date: Date? {
        switch previewType {
        case .sent(let linkPreview, _):
            linkPreview.date
        case .draft(let linkPreviewDraft):
            linkPreviewDraft.date
        }
    }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}

public class CommonCallLinksUI {
    public static func callLinkIcon(rootKey: CallLinkRootKey) -> UIImage? {
        guard let image = UIImage(named: "video-compact") else { return nil }
        let newSize = CGSize(square: Constants.circleViewDimension)

        let theme = AvatarTheme.forData(rootKey.bytes.prefix(1))

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let finalImage = renderer.image { context in
            let rect = CGRect(origin: .zero, size: newSize)
            let circlePath = UIBezierPath(ovalIn: rect)

            theme.backgroundColor.setFill()
            circlePath.fill()

            context.cgContext.addPath(circlePath.cgPath)
            context.cgContext.clip()

            theme.foregroundColor.set()
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
    }
}
