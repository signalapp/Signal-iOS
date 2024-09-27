//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: -

class LinkPreviewGroupLink: LinkPreviewState {
    private let linkPreview: OWSLinkPreview
    public let linkType: LinkPreviewLinkType
    private let groupInviteLinkViewModel: GroupInviteLinkViewModel

    private var groupInviteLinkPreview: GroupInviteLinkPreview? {
        groupInviteLinkViewModel.groupInviteLinkPreview
    }

    private let _conversationStyle: ConversationStyle
    var conversationStyle: ConversationStyle? {
        _conversationStyle
    }

    init(
        linkType: LinkPreviewLinkType,
        linkPreview: OWSLinkPreview,
        groupInviteLinkViewModel: GroupInviteLinkViewModel,
        conversationStyle: ConversationStyle
    ) {
        self.linkPreview = linkPreview
        self.linkType = linkType
        self.groupInviteLinkViewModel = groupInviteLinkViewModel
        _conversationStyle = conversationStyle
    }

    var isLoaded: Bool { groupInviteLinkPreview != nil }

    var urlString: String? {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url")
            return nil
        }
        return urlString
    }

    var displayDomain: String? {
        guard let displayDomain = linkPreview.displayDomain else {
            Logger.error("Missing display domain")
            return nil
        }
        return displayDomain
    }

    var title: String? {
        groupInviteLinkPreview?.title.filterForDisplay.nilIfEmpty
    }

    var imageState: LinkPreviewImageState {
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

    func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState == .loaded)

        let groupInviteLinkViewModel = self.groupInviteLinkViewModel
        DispatchQueue.global().async {
            guard let avatar = groupInviteLinkViewModel.avatar, avatar.isValid else {
                return
            }
            guard let image = UIImage(contentsOfFile: avatar.cacheFileUrl.path) else {
                owsFailDebug("Couldn't load group avatar.")
                return
            }
            completion(image)
        }
    }

    func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        let urlString = groupInviteLinkViewModel.url.absoluteString
        return .init(id: nil, urlString: urlString, thumbnailQuality: thumbnailQuality)
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil, lock: .sharedGlobal)

    var imagePixelSize: CGSize {
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

    var previewDescription: String? {
        guard let groupInviteLinkPreview = groupInviteLinkPreview else {
            Logger.warn("Missing groupInviteLinkPreview.")
            return nil
        }
        let groupIndicator = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_GROUP_INDICATOR",
            comment: "Indicator for group conversations in the 'group invite link' action sheet."
        )
        let memberCount = GroupViewUtils.formatGroupMembersLabel(memberCount: Int(groupInviteLinkPreview.memberCount))
        return groupIndicator + " | " + memberCount
    }

    var date: Date? { linkPreview.date }

    let isGroupInviteLink = true

    var activityIndicatorStyle: UIActivityIndicatorView.Style {
        switch linkType {
        case .incomingMessageGroupInviteLink:
            return .medium
        case .outgoingMessageGroupInviteLink:
            return .medium
        default:
            return LinkPreviewView.defaultActivityIndicatorStyle
        }
    }
}

// MARK: -

class GroupInviteLinkViewModel: Equatable {

    let url: URL
    let groupInviteLinkPreview: GroupInviteLinkPreview?
    let avatar: GroupInviteLinkCachedAvatar?
    let isExpired: Bool
    var isLoaded: Bool {
        groupInviteLinkPreview != nil
    }

    init(
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

    static func == (lhs: GroupInviteLinkViewModel, rhs: GroupInviteLinkViewModel) -> Bool {
        return lhs.url == rhs.url &&
        lhs.groupInviteLinkPreview == rhs.groupInviteLinkPreview &&
        lhs.avatar == rhs.avatar
    }
}

// MARK: -

class GroupInviteLinkCachedAvatar: Equatable {

    let cacheFileUrl: URL
    let imageSizePixels: CGSize
    let isValid: Bool

    init(
        cacheFileUrl: URL,
        imageSizePixels: CGSize,
        isValid: Bool
    ) {
        self.cacheFileUrl = cacheFileUrl
        self.imageSizePixels = imageSizePixels
        self.isValid = isValid
    }

    static func == (lhs: GroupInviteLinkCachedAvatar, rhs: GroupInviteLinkCachedAvatar) -> Bool {
        return lhs.cacheFileUrl == rhs.cacheFileUrl &&
        lhs.imageSizePixels == rhs.imageSizePixels &&
        lhs.isValid == rhs.isValid
    }
}
