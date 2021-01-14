//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum ThemeIcon: UInt {
    case settingsAllMedia
    case settingsBlock
    case settingsColorPalette
    case settingsEditGroup
    case settingsLeaveGroup
    case settingsMessageSound
    case settingsMuted
    case settingsProfile
    case settingsTimer
    case settingsTimerDisabled
    case settingsSearch
    case settingsShowGroup
    case settingsViewSafetyNumber
    case settingsUserInContacts
    case settingsAddToContacts
    case settingsAddMembers
    case settingsShowAllMembers
    case settingsEditGroupAccess
    case settingsViewMakeGroupAdmin
    case settingsViewRevokeGroupAdmin
    case settingsViewRemoveFromGroup
    case settingsViewRequestAndInvites
    case settingsAddToGroup
    case settingsMention
    case settingsLink

    case stickerButton
    case cameraButton
    case micButton

    case attachmentCamera
    case attachmentContact
    case attachmentFile
    case attachmentGif
    case attachmentLocation

    case messageActionReply
    case messageActionForward
    case messageActionCopy
    case messageActionShare
    case messageActionDelete
    case messageActionSave
    case messageActionSelect

    case compose24
    case composeNewGroup
    case composeFindByPhoneNumber
    case composeInvite
    case compose32

    case checkCircle
    case message
    case audioCall
    case videoCall
    case info
    case groupMessage
    case profileChangeMessage

    case check16
    case compose16
    case error16
    case group16
    case heart16
    case info16
    case leave16
    case megaphone16
    case memberAccepted16
    case memberAdded16
    case memberDeclined16
    case memberRemove16
    case phoneIncoming16
    case phoneoutgoing16
    case phoneX16
    case photo16
    case profile16
    case retry24
    case safetyNumber16
    case timerDisabled16
    case timer16
    case videoIncoming16
    case videoOutgoing16
    case videoX16
    case refresh16

    case transfer
    case register

    case emojiActivity
    case emojiAnimal
    case emojiFlag
    case emojiFood
    case emojiObject
    case emojiSmiley
    case emojiSymbol
    case emojiTravel
    case emojiRecent
}

// MARK: - Colors

@objc
public extension Theme {
    @objc(launchScreenBackgroundColor)
    class var launchScreenBackground: UIColor {
        // We only adapt for dark theme on iOS 13+, because only iOS 13 supports
        // handling dark / light appearance in the launch screen storyboard.
        guard #available(iOS 13, *) else { return .ows_signalBlue }
        return Theme.isDarkThemeEnabled ? .ows_signalBlueDark : .ows_signalBlue
    }

    class var selectedConversationCellColor: UIColor {
        return Theme.isDarkThemeEnabled ? UIColor.ows_whiteAlpha20 : UIColor.ows_accentBlue.withAlphaComponent(0.15)
    }
}

// MARK: - Icons

@objc
public extension Theme {
    class func iconImage(_ icon: ThemeIcon) -> UIImage {
        let name = iconName(icon)
        guard let image = UIImage(named: name) else {
            owsFailDebug("image was unexpectedly nil: \(name)")
            return UIImage()
        }

        return image.withRenderingMode(.alwaysTemplate)
    }

    class func iconName(_ icon: ThemeIcon) -> String {
        switch icon {
        case .settingsUserInContacts:
            return isDarkThemeEnabled ? "profile-circle-solid-24" : "profile-circle-outline-24"
        case .settingsAddToContacts:
            return "plus-24"
        case .settingsAllMedia:
            return isDarkThemeEnabled ? "photo-album-solid-24" : "photo-album-outline-24"
        case .settingsEditGroup:
            return isDarkThemeEnabled ? "compose-solid-24" : "compose-outline-24"
        case .settingsLeaveGroup:
            return "leave-24"
        case .settingsViewSafetyNumber:
            return isDarkThemeEnabled ? "safety-number-solid-24" : "safety-number-outline-24"
        case .settingsProfile:
            return isDarkThemeEnabled ? "profile-solid-24" : "profile-outline-24"
        case .settingsShowGroup:
            return isDarkThemeEnabled ? "group-solid-24" : "group-outline-24"
        case .settingsEditGroupAccess:
            return isDarkThemeEnabled ? "group-solid-24" : "group-outline-24"
        case .settingsViewMakeGroupAdmin:
            return isDarkThemeEnabled ? "group-solid-24" : "group-outline-24"
        case .settingsViewRevokeGroupAdmin:
            return isDarkThemeEnabled ? "group-solid-24" : "group-outline-24"
        case .settingsViewRemoveFromGroup:
            return "leave-24"
        case .settingsViewRequestAndInvites:
            return "pending-invite-24"
        case .settingsTimer:
            return "timer-24"
        case .settingsTimerDisabled:
            return "timer-disabled-24"
        case .settingsMessageSound:
            return isDarkThemeEnabled ? "sound-solid-24" : "sound-outline-24"
        case .settingsMuted:
            return isDarkThemeEnabled ? "bell-disabled-solid-24" : "bell-disabled-outline-24"
        case .settingsBlock:
            return "block-24"
        case .settingsColorPalette:
            // TODO NEEDS_ASSET - waiting on design to provide an updated asset.
            return "ic_color_palette"
        case .settingsSearch:
            return "search-24"
        case .settingsAddMembers:
            return "plus-256"
        case .settingsShowAllMembers:
            return "chevron-down-256"
        case .settingsAddToGroup:
            return isDarkThemeEnabled ? "group-solid-24" : "group-outline-24"
        case .settingsMention:
            return "mention-24"
        case .settingsLink:
            return "link-24"

        // Input Toolbar
        case .stickerButton:
            return isDarkThemeEnabled ? "sticker-solid-24" : "sticker-outline-24"
        case .cameraButton:
            return isDarkThemeEnabled ? "camera-solid-24" : "camera-outline-24"
        case .micButton:
            return isDarkThemeEnabled ? "mic-solid-24" : "mic-outline-24"
        case .attachmentCamera:
            return "camera-outline-32"
        case .attachmentContact:
            return "contact-outline-32"
        case .attachmentFile:
            return "file-outline-32"
        case .attachmentGif:
            return "gif-outline-32"
        case .attachmentLocation:
            return "location-outline-32"

        case .messageActionReply:
            return isDarkThemeEnabled ? "reply-filled-24" : "reply-outline-24"
        case .messageActionForward:
            return isDarkThemeEnabled ? "forward-solid-24" : "forward-outline-24"
        case .messageActionCopy:
            return isDarkThemeEnabled ? "copy-solid-24" : "ic_copy"
        case .messageActionShare:
            // There is no separate dark theme version of this icon, by design.
            return "share-ios-24"
        case .messageActionDelete:
            return isDarkThemeEnabled ? "trash-solid-24" : "trash-outline-24"
        case .messageActionSave:
            // There is no separate dark theme version of this icon, by design.
            return "save-24"
        case .messageActionSelect:
            return "select-24"

        case .compose24:
            return isDarkThemeEnabled ? "compose-solid-24" : "compose-outline-24"
        case .composeNewGroup:
            return "group-outline-256"
        case .composeFindByPhoneNumber:
            return "phone-number-256"
        case .composeInvite:
            return "invite-outline-256"
        case .compose32:
            return isDarkThemeEnabled ? "compose-solid-32" : "compose-outline-32"

        case .checkCircle:
            return isDarkThemeEnabled ? "check-circle-solid-24" : "check-circle-outline-24"
        case .message:
            return isDarkThemeEnabled ? "message-solid-24" : "message-outline-24"
        case .audioCall:
            return isDarkThemeEnabled ? "phone-solid-24" : "phone-outline-24"
        case .videoCall:
            return isDarkThemeEnabled ? "video-solid-24" : "video-outline-24"
        case .info:
            return isDarkThemeEnabled ? "info-solid-24" : "ic_info"
        case .groupMessage:
            return "group-outline-20"
        case .profileChangeMessage:
            return isDarkThemeEnabled ? "profile-solid-20" : "profile-outline-20"

        case .check16:
            return isDarkThemeEnabled ? "check-solid-16" : "check-outline-16"
        case .compose16:
            return isDarkThemeEnabled ? "compose-solid-16" : "compose-outline-16"
        case .error16:
            return isDarkThemeEnabled ? "error-solid-16" : "error-outline-16"
        case .group16:
            return isDarkThemeEnabled ? "group-solid-16" : "group-outline-16"
        case .heart16:
            return isDarkThemeEnabled ? "heart-solid-16" : "heart-outline-16"
        case .info16:
            return isDarkThemeEnabled ? "info-solid-16" : "info-outline-16"
        case .leave16:
            return isDarkThemeEnabled ? "leave-solid-16" : "leave-outline-16"
        case .megaphone16:
            return isDarkThemeEnabled ? "megaphone-solid-16" : "megaphone-outline-16"
        case .memberAccepted16:
            return isDarkThemeEnabled ? "member-accepted-solid-16" : "member-accepted-outline-16"
        case .memberAdded16:
            return isDarkThemeEnabled ? "member-added-solid-16" : "member-added-outline-16"
        case .memberDeclined16:
            return isDarkThemeEnabled ? "member-declined-solid-16" : "member-declined-outline-16"
        case .memberRemove16:
            return isDarkThemeEnabled ? "member-remove-solid-16" : "member-remove-outline-16"
        case .phoneIncoming16:
            return isDarkThemeEnabled ? "phone-incoming-solid-16" : "phone-incoming-outline-16"
        case .phoneoutgoing16:
            return isDarkThemeEnabled ? "phone-outgoing-solid-16" : "phone-outgoing-outline-16"
        case .phoneX16:
            return isDarkThemeEnabled ? "phone-x-solid-16" : "phone-x-outline-16"
        case .photo16:
            return isDarkThemeEnabled ? "photo-solid-16" : "photo-outline-16"
        case .profile16:
            return isDarkThemeEnabled ? "profile-solid-16" : "profile-outline-16"
        case .retry24:
            return "retry-24"
        case .safetyNumber16:
            return isDarkThemeEnabled ? "safety-number-solid-16" : "safety-number-outline-16"
        case .timerDisabled16:
            return isDarkThemeEnabled ? "timer-disabled-solid-16" : "timer-disabled-outline-16"
        case .timer16:
            return isDarkThemeEnabled ? "timer-solid-16" : "timer-outline-16"
        case .videoIncoming16:
            return isDarkThemeEnabled ? "video-incoming-solid-16" : "video-incoming-outline-16"
        case .videoOutgoing16:
            return isDarkThemeEnabled ? "video-outgoing-solid-16" : "video-outgoing-outline-16"
        case .videoX16:
            return isDarkThemeEnabled ? "video-x-solid-16" : "video-x-outline-16"
        case .refresh16:
            return "refresh-16"

        case .transfer:
            return "transfer-\(UIDevice.current.isIPad ? "ipad" : "phone")-outline-60-\(isDarkThemeEnabled ? "dark" : "light")"
        case .register:
            return "register-\(UIDevice.current.isIPad ? "ipad" : "phone")-outline-60-\(isDarkThemeEnabled ? "dark" : "light")"

        case .emojiActivity:
            return "emoji-activity-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiAnimal:
            return "emoji-animal-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiFlag:
            return "emoji-flag-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiFood:
            return "emoji-food-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiObject:
            return "emoji-object-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiSmiley:
            return "emoji-smiley-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiSymbol:
            return "emoji-symbol-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiTravel:
            return "emoji-travel-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        case .emojiRecent:
            return "recent-\(isDarkThemeEnabled ? "solid" : "outline")-20"
        }
    }
}

extension Theme {

    // Bridging the old name to new name for our ObjC friends
    @objc
    public static var actionSheetBackgroundColor: UIColor {
        return ActionSheet.default.backgroundColor
    }

    public enum ActionSheet {
        case `default`
        case translucentDark

        public var hairlineColor: UIColor {
            switch self {
            case .default: return isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
            case .translucentDark: return .ows_whiteAlpha20
            }
        }

        public var headerTitleColor: UIColor {
            switch self {
            case .default: return Theme.primaryTextColor
            case .translucentDark: return Theme.darkThemePrimaryColor
            }
        }

        public var headerMessageColor: UIColor {
            switch self {
            case .default: return Theme.primaryTextColor
            case .translucentDark: return Theme.darkThemeSecondaryTextAndIconColor
            }
        }

        public var buttonTextColor: UIColor {
            switch self {
            case .default: return Theme.primaryTextColor
            case .translucentDark: return Theme.darkThemePrimaryColor
            }
        }

        public var safetyNumberChangeButtonBackgroundColor: UIColor {
            switch self {
            case .default: return Theme.conversationButtonBackgroundColor
            case .translucentDark: return .ows_gray75
            }
        }

        public var safetyNumberChangeButtonTextColor: UIColor {
            switch self {
            case .default: return Theme.conversationButtonTextColor
            case .translucentDark: return .ows_accentBlueDark
            }
        }

        public var destructiveButtonTextColor: UIColor {
            return .ows_accentRed
        }

        public var buttonHighlightColor: UIColor {
            switch self {
            case .default: return Theme.cellSelectedColor
            case .translucentDark: return .ows_whiteAlpha20
            }
        }

        public var backgroundColor: UIColor {
            switch self {
            case .default: return isDarkThemeEnabled ? .ows_gray75 : .ows_white
            case .translucentDark: return .clear
            }
        }

        public func createBackgroundView() -> UIView {
            switch self {
            case .default:
                let background = UIView()
                background.backgroundColor = backgroundColor
                return background
            case .translucentDark:
                let background = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
                return background
            }
        }
    }
}
