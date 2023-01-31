//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: -

public class LinkPreviewGroupLink: LinkPreviewState {

    private let linkPreview: OWSLinkPreview
    public let linkType: LinkPreviewLinkType
    private let groupInviteLinkViewModel: GroupInviteLinkViewModel

    private var groupInviteLinkPreview: GroupInviteLinkPreview? {
        groupInviteLinkViewModel.groupInviteLinkPreview
    }

    private let _conversationStyle: ConversationStyle
    public var conversationStyle: ConversationStyle? {
        _conversationStyle
    }

    public required init(linkType: LinkPreviewLinkType,
                         linkPreview: OWSLinkPreview,
                         groupInviteLinkViewModel: GroupInviteLinkViewModel,
                         conversationStyle: ConversationStyle) {
        self.linkPreview = linkPreview
        self.linkType = linkType
        self.groupInviteLinkViewModel = groupInviteLinkViewModel
        _conversationStyle = conversationStyle
    }

    public var isLoaded: Bool { groupInviteLinkPreview != nil }

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
        groupInviteLinkPreview?.title.filterForDisplay.nilIfEmpty
    }

    public var imageState: LinkPreviewImageState {
        if let avatar = groupInviteLinkViewModel.avatar {
            if avatar.isValid {
                return .loaded
            } else {
                return .invalid
            }
        }
        guard groupInviteLinkPreview?.avatarUrlPath != nil else {
            return .none
        }
        return .loading
    }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality,
                           completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState == .loaded)

        let groupInviteLinkViewModel = self.groupInviteLinkViewModel
        DispatchQueue.global().async {
            guard let avatar = groupInviteLinkViewModel.avatar,
                  avatar.isValid else {
                return
            }
            guard let image = UIImage(contentsOfFile: avatar.cacheFileUrl.path) else {
                owsFailDebug("Couldn't load group avatar.")
                return
            }
            completion(image)
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> String? {
        let urlString = groupInviteLinkViewModel.url.absoluteString
        return "\(urlString).\(NSStringForAttachmentThumbnailQuality(thumbnailQuality))"
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil)

    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        guard let avatar = groupInviteLinkViewModel.avatar else {
            return CGSize.zero
        }
        let result = avatar.imageSizePixels
        imagePixelSizeCache.set(result)
        return result
    }

    public var previewDescription: String? {
        guard let groupInviteLinkPreview = groupInviteLinkPreview else {
            Logger.warn("Missing groupInviteLinkPreview.")
            return nil
        }
        let groupIndicator = OWSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_GROUP_INDICATOR",
                                               comment: "Indicator for group conversations in the 'group invite link' action sheet.")
        let memberCount = GroupViewUtils.formatGroupMembersLabel(memberCount: Int(groupInviteLinkPreview.memberCount))
        return groupIndicator + " | " + memberCount
    }

    public var date: Date? { linkPreview.date }

    public let isGroupInviteLink = true

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
}

// MARK: -

public class GroupInviteLinkViewModel: Equatable {

    public let url: URL
    public let groupInviteLinkPreview: GroupInviteLinkPreview?
    public let avatar: GroupInviteLinkCachedAvatar?
    public let isExpired: Bool
    public var isLoaded: Bool {
        groupInviteLinkPreview != nil
    }

    public init(
        url: URL,
        groupInviteLinkPreview: GroupInviteLinkPreview?,
        avatar: GroupInviteLinkCachedAvatar?,
        isExpired: Bool
    ) {
        self.url = url
        self.groupInviteLinkPreview = groupInviteLinkPreview
        self.avatar = avatar
        self.isExpired = isExpired
    }

    public static func == (lhs: GroupInviteLinkViewModel, rhs: GroupInviteLinkViewModel) -> Bool {
        return lhs.url == rhs.url &&
        lhs.groupInviteLinkPreview == rhs.groupInviteLinkPreview &&
        lhs.avatar == rhs.avatar
    }
}

// MARK: -

public class GroupInviteLinkCachedAvatar: Equatable {

    public let cacheFileUrl: URL
    public let imageSizePixels: CGSize
    public let isValid: Bool

    public init(
        cacheFileUrl: URL,
        imageSizePixels: CGSize,
        isValid: Bool
    ) {
        self.cacheFileUrl = cacheFileUrl
        self.imageSizePixels = imageSizePixels
        self.isValid = isValid
    }

    public static func == (lhs: GroupInviteLinkCachedAvatar, rhs: GroupInviteLinkCachedAvatar) -> Bool {
        return lhs.cacheFileUrl == rhs.cacheFileUrl &&
        lhs.imageSizePixels == rhs.imageSizePixels &&
        lhs.isValid == rhs.isValid
    }
}
