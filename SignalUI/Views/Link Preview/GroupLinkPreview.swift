//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: -

@objc
public class LinkPreviewGroupLink: NSObject, LinkPreviewState {

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

    @objc
    public required init(linkType: LinkPreviewLinkType,
                         linkPreview: OWSLinkPreview,
                         groupInviteLinkViewModel: GroupInviteLinkViewModel,
                         conversationStyle: ConversationStyle) {
        self.linkPreview = linkPreview
        self.linkType = linkType
        self.groupInviteLinkViewModel = groupInviteLinkViewModel
        _conversationStyle = conversationStyle
    }

    public func isLoaded() -> Bool {
        groupInviteLinkPreview != nil
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
        guard let value = groupInviteLinkPreview?.title.filterForDisplay,
            value.count > 0 else {
                return nil
        }
        return value
    }

    public func imageState() -> LinkPreviewImageState {
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
        owsAssertDebug(imageState() == .loaded)

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

    @objc
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

    public func previewDescription() -> String? {
        guard let groupInviteLinkPreview = groupInviteLinkPreview else {
            Logger.warn("Missing groupInviteLinkPreview.")
            return nil
        }
        let groupIndicator = OWSLocalizedString("GROUP_LINK_ACTION_SHEET_VIEW_GROUP_INDICATOR",
                                               comment: "Indicator for group conversations in the 'group invite link' action sheet.")
        let memberCount = GroupViewUtils.formatGroupMembersLabel(memberCount: Int(groupInviteLinkPreview.memberCount))
        return groupIndicator + " | " + memberCount
    }

    public func date() -> Date? {
        linkPreview.date
    }

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

@objc
public class GroupInviteLinkViewModel: NSObject {
    @objc
    public let url: URL

    public let groupInviteLinkPreview: GroupInviteLinkPreview?

    public let avatar: GroupInviteLinkCachedAvatar?

    @objc
    public let isExpired: Bool

    @objc
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

    @objc
    public override func isEqual(_ object: Any!) -> Bool {
        guard let other = object as? GroupInviteLinkViewModel else {
            return false
        }
        return (self.url == other.url &&
            self.groupInviteLinkPreview == other.groupInviteLinkPreview &&
            self.avatar == other.avatar)
    }
}

// MARK: -

@objcMembers
public class GroupInviteLinkCachedAvatar: NSObject {
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

    public override func isEqual(_ object: Any!) -> Bool {
        guard let other = object as? GroupInviteLinkCachedAvatar else {
            return false
        }
        return (self.cacheFileUrl == other.cacheFileUrl &&
            self.imageSizePixels == other.imageSizePixels &&
            self.isValid == other.isValid)
    }
}
