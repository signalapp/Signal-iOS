//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    case settingsWallpaper
    case settingsAccount
    case settingsManage
    case settingsLinkedDevices
    case settingsAppearance
    case settingsChats
    case settingsStories
    case settingsNotifications
    case settingsPrivacy
    case settingsDataUsage
    case settingsHelp
    case settingsInvite
    case settingsDonate
    case settingsAdvanced
    case settingsAbout
    case settingsPayments
    case settingsBadges
    case settingsReceipts
    case settingsGift
    case settingsShareUsername

    case cameraButton
    case micButton
    case messageActionSpeak
    case messageActionStopSpeaking

    case attachmentCamera
    case attachmentContact
    case attachmentFile
    case attachmentGif
    case attachmentLocation
    case attachmentPayment

    case messageActionReply
    case messageActionForward20
    case messageActionForward24
    case messageActionCopy
    case messageActionShare20
    case messageActionShare24
    case messageActionDelete
    case messageActionSave20
    case messageActionSave24
    case messageActionSelect

    case contextMenuSelect
    case contextMenuInfo20
    case contextMenuInfo24

    case compose24
    case composeNewGroup
    case composeFindByPhoneNumber
    case composeInvite
    case composeNewGroupLarge
    case composeFindByPhoneNumberLarge
    case composeInviteLarge
    case compose32
    case cancel20
    case search20

    case trash20
    case trash24
    case copy24
    case color24
    case text24
    case cancel24
    case xCircle24
    case open20
    case open24
    case more16
    case more24

    case checkCircle20
    case checkCircle24
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
    case paymentNotification
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
    case emojiSettings

    case sealedSenderIndicator
    case accessoryCheckmark
    case empty

    case profilePlaceholder

    case hide20
    case hide24
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
        iconImage(icon, isDarkThemeEnabled: isDarkThemeEnabled)
    }

    class func iconImage(_ icon: ThemeIcon, isDarkThemeEnabled: Bool) -> UIImage {
        let name = iconName(icon, isDarkThemeEnabled: isDarkThemeEnabled)
        guard let image = UIImage(named: name) else {
            owsFailDebug("image was unexpectedly nil: \(name)")
            return UIImage()
        }

        return image.withRenderingMode(.alwaysTemplate)
    }

    class func iconName(_ icon: ThemeIcon) -> String {
        iconName(icon, isDarkThemeEnabled: isDarkThemeEnabled)
    }

    class func iconName(_ icon: ThemeIcon, isDarkThemeEnabled: Bool) -> String {
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
            return "at-icon"
        case .settingsLink:
            return "link-24"
        case .settingsWallpaper:
            return isDarkThemeEnabled ? "wallpaper-solid-24" : "wallpaper-outline-24"
        case .settingsAccount:
            return isDarkThemeEnabled ? "profile-circle-solid-24" : "profile-circle-outline-24"
        case .settingsManage:
            return isDarkThemeEnabled ? "manage-solid-24" : "manage-outline-24"
        case .settingsLinkedDevices:
            return "linked-devices-24"
        case .settingsAppearance:
            return isDarkThemeEnabled ? "appearance-solid-24" : "appearance-outline-24"
        case .settingsChats:
            return isDarkThemeEnabled ? "message-solid-24" : "message-outline-24"
        case .settingsStories:
            return isDarkThemeEnabled ? "stories-24-solid" : "stories-24-outline"
        case .settingsNotifications:
            return isDarkThemeEnabled ? "bell-solid-24" : "bell-outline-24"
        case .settingsPrivacy:
            return isDarkThemeEnabled ? "lock-solid-24" : "lock-outline-24"
        case .settingsDataUsage:
            return isDarkThemeEnabled ? "archive-solid-24" : "archive-outline-24"
        case .settingsHelp:
            return isDarkThemeEnabled ? "help-solid-24" : "help-outline-24"
        case .settingsInvite:
            return isDarkThemeEnabled ? "invite-solid-24" : "invite-outline-24"
        case .settingsDonate:
            return isDarkThemeEnabled ? "heart-solid-24" : "heart-outline-24"
        case .settingsAdvanced:
            return "advanced-24"
        case .settingsAbout:
            return isDarkThemeEnabled ? "compose-solid-24" : "compose-outline-24"
        case .settingsPayments:
            return isDarkThemeEnabled ? "payments-solid-24" : "payments-outline-24"
        case .settingsBadges:
            return isDarkThemeEnabled ? "badge-solid-24" : "badge-outline-24"
        case .settingsReceipts:
            return isDarkThemeEnabled ? "receipts-solid-24" : "receipts-outline-24"
        case .settingsGift:
            return isDarkThemeEnabled ? "gift-solid-24" : "gift-outline-24"
        case .settingsShareUsername:
            return "share-outline-20"

        // Input Toolbar
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
        case .attachmentPayment:
            return "payments-outline-32"
        case .messageActionReply:
            return isDarkThemeEnabled ? "reply-filled-24" : "reply-outline-24"
        case .messageActionForward20:
            return isDarkThemeEnabled ? "forward-solid-20" : "forward-outline-20"
        case .messageActionForward24:
            return isDarkThemeEnabled ? "forward-solid-24" : "forward-outline-24"
        case .messageActionCopy:
            return isDarkThemeEnabled ? "copy-solid-24" : "ic_copy"
        case .messageActionShare20:
            return isDarkThemeEnabled ? "share-solid-20" : "share-outline-20"
        case .messageActionShare24:
            return isDarkThemeEnabled ? "share-solid-24" : "share-outline-24"
        case .messageActionSpeak:
            return "speaker-solid-28"
        case .messageActionStopSpeaking:
            return "pause-filled-24"
        case .messageActionDelete:
            return isDarkThemeEnabled ? "trash-solid-24" : "trash-outline-24"
        case .messageActionSave20:
            return isDarkThemeEnabled ? "save-solid-20" : "save-outline-20"
        case .messageActionSave24:
            return isDarkThemeEnabled ? "save-solid-24" : "save-outline-24"
        case .messageActionSelect:
            return "select-24"
        case .contextMenuSelect:
            return isDarkThemeEnabled ? "check-circle-solid-24" : "check-circle-outline-24"
        case .contextMenuInfo20:
            return isDarkThemeEnabled ? "info-solid-20" : "info-outline-20"
        case .contextMenuInfo24:
            return isDarkThemeEnabled ? "info-solid-24" : "info-outline-24"
        case .compose24:
            return isDarkThemeEnabled ? "compose-solid-24" : "compose-outline-24"
        case .composeNewGroup:
            return isDarkThemeEnabled ? "group-solid-24" : "group-outline-24"
        case .composeFindByPhoneNumber:
            return "hashtag-24"
        case .composeInvite:
            return isDarkThemeEnabled ? "invite-solid-24" : "invite-outline-24"
        case .composeNewGroupLarge:
            return "group-outline-256"
        case .composeFindByPhoneNumberLarge:
            return "phone-number-256"
        case .composeInviteLarge:
            return "invite-outline-256"
        case .compose32:
            return isDarkThemeEnabled ? "compose-solid-32" : "compose-outline-32"
        case .cancel20:
            return "x-20"
        case .cancel24:
            return "x-24"
        case .search20:
            return "search-20"
        case .xCircle24:
            return isDarkThemeEnabled ? "x-circle-solid-24" : "x-circle-outline-24"
        case .open20:
            return isDarkThemeEnabled ? "open-solid-20" : "open-outline-20"
        case .open24:
            return isDarkThemeEnabled ? "open-solid-24" : "open-outline-24"
        case .more16:
            return "more-horiz-16"
        case .more24:
            return "more-horiz-24"

        case .trash20:
            return isDarkThemeEnabled ? "trash-solid-20" : "trash-outline-20"
        case .trash24:
            return isDarkThemeEnabled ? "trash-solid-24" : "trash-outline-24"
        case .copy24:
            return isDarkThemeEnabled ? "copy-solid-24" : "ic_copy"
        case .color24:
            return isDarkThemeEnabled ? "color-solid-24" : "color-outline-24"
        case .text24:
            return "text-24"

        case .checkCircle20:
            return isDarkThemeEnabled ? "check-circle-solid-20" : "check-circle-outline-20"
        case .checkCircle24:
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
        case .paymentNotification:
            return isDarkThemeEnabled ? "payments-solid-24" : "payments-outline-24"
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
        case .emojiSettings:
            return "emoji-settings-\(isDarkThemeEnabled ? "solid" : "outline")-24"

        case .sealedSenderIndicator:
            return isDarkThemeEnabled ? "unidentified-delivery-solid-20" : "unidentified-delivery-outline-20"
        case .accessoryCheckmark:
            return "accessory-checkmark-24"
        case .empty:
            return "empty-24"

        case .profilePlaceholder:
            return isDarkThemeEnabled ? "profile-placeholder-dark-56" : "profile-placeholder-56"

        case .hide20:
            return isDarkThemeEnabled ? "hide-solid-20" : "hide-outline-20"
        case .hide24:
            return isDarkThemeEnabled ? "hide-solid-24" : "hide-outline-24"
        }
    }
}

// MARK: -

extension Theme {

    // Bridging the old name to new name for our ObjC friends
    @objc
    public static var actionSheetBackgroundColor: UIColor {
        return ActionSheet.default.backgroundColor
    }

    public enum ActionSheet {
        case `default`
        case grouped
        case translucentDark

        public var hairlineColor: UIColor {
            switch self {
            case .default, .grouped: return isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
            case .translucentDark: return .ows_whiteAlpha20
            }
        }

        public var headerTitleColor: UIColor {
            switch self {
            case .default, .grouped: return Theme.primaryTextColor
            case .translucentDark: return Theme.darkThemePrimaryColor
            }
        }

        public var headerMessageColor: UIColor {
            switch self {
            case .default, .grouped: return Theme.primaryTextColor
            case .translucentDark: return Theme.darkThemeSecondaryTextAndIconColor
            }
        }

        public var buttonTextColor: UIColor {
            switch self {
            case .default, .grouped: return Theme.primaryTextColor
            case .translucentDark: return Theme.darkThemePrimaryColor
            }
        }

        public var safetyNumberChangeButtonBackgroundColor: UIColor {
            switch self {
            case .default, .grouped: return Theme.conversationButtonBackgroundColor
            case .translucentDark: return .ows_gray75
            }
        }

        public var safetyNumberChangeButtonTextColor: UIColor {
            switch self {
            case .default, .grouped: return Theme.conversationButtonTextColor
            case .translucentDark: return .ows_accentBlueDark
            }
        }

        public var destructiveButtonTextColor: UIColor {
            return .ows_accentRed
        }

        public var buttonHighlightColor: UIColor {
            switch self {
            case .default, .grouped: return Theme.cellSelectedColor
            case .translucentDark: return .ows_whiteAlpha20
            }
        }

        public var backgroundColor: UIColor {
            switch self {
            case .default: return isDarkThemeEnabled ? .ows_gray75 : .ows_white
            case .grouped: return Theme.tableView2BackgroundColor
            case .translucentDark: return .clear
            }
        }

        public func createBackgroundView() -> UIView {
            switch self {
            case .default, .grouped:
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

// MARK: -

@objc
public extension UIImageView {
    func setThemeIcon(_ themeIcon: ThemeIcon, tintColor: UIColor) {
        self.setTemplateImageName(Theme.iconName(themeIcon), tintColor: tintColor)
    }
}
