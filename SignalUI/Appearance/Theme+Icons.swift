//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public enum ThemeIcon: UInt {
    case settingsAccount
    case settingsLinkedDevices
    case settingsDonate
    case settingsAppearance
    case settingsChats
    case settingsStories
    case settingsNotifications
    case settingsPrivacy
    case settingsDataUsage
    case settingsPayments
    case settingsHelp
    case settingsInvite
    case settingsAdvanced

    case donateManageSubscription
    case donateBadges
    case donateGift
    case donateReceipts

    case profileName
    case profileUsername
    case profileAbout
    case profileBadges

    case chatSettingsTimerOn
    case chatSettingsTimerOff
    case chatSettingsWallpaper
    case chatSettingsMessageSound
    case chatSettingsBlock
    case chatSettingsMute
    case chatSettingsMentions
    case contactInfoSafetyNumber
    case contactInfoUserInContacts
    case contactInfoAddToContacts
    case contactInfoSignalConnection
    case contactInfoPhone
    case contactInfoGroups
    case groupInfoLeaveGroup
    case groupInfoAddMembers
    case groupInfoShowAllMembers
    case groupInfoGroupLink
    case groupInfoRequestAndInvites
    case groupInfoPermissions
    case groupInfoEditName
    case groupInfoEditDescription
    case groupMemberRemoveFromGroup
    case groupMemberMakeGroupAdmin
    case groupMemberRevokeGroupAdmin
    case groupMemberAddToGroup

    case genericGroup
    case genericStories
    case phoneNumber
    case checkCircle
    case checkCircleFill
    case checkmark
    case circle
    case arrowDown
    case arrowUp
    case arrowRight
    case chevronUp
    case chevronDown
    case maximize
    case minimize
    case refresh
    case official
    case qrCode
    case qrCodeLight

    case buttonCamera
    case buttonMicrophone
    case buttonVoiceCall
    case buttonVideoCall
    case buttonNewCall
    case buttonMessage
    case buttonPhotoLibrary
    case buttonCompose
    case buttonEdit
    case buttonMute
    case buttonDelete
    case buttonSearch
    case buttonForward
    case buttonShare
    case buttonSave
    case buttonCopy
    case buttonMore
    case buttonText
    case buttonX
    case buttonRetry
    case buttonLink

    case contextMenuSave
    case contextMenuDelete
    case contextMenuReply
    case contextMenuInfo
    case contextMenuCopy
    case contextMenuShare
    case contextMenuForward
    case contextMenuSelect
    case contextMenuSpeak
    case contextMenuStopSpeaking
    case contextMenuSettings
    case contextMenuArchive
    case contextMenuEdit
    case contextMenuPrivacy
    case contextMenuXCircle
    case contextMenuOpenInChat
    case contextMenuVoiceCall
    case contextMenuVideoCall

    case composeNewGroupLarge
    case composeFindByPhoneNumberLarge
    case composeInviteLarge

    case check16
    case compose16
    case error16
    case group16
    case heart16
    case info16
    case leave16
    case megaphone16
    case memberAdded16
    case memberDeclined16
    case memberRemove16
    case photo16
    case phone16
    case phoneFill16
    case video16
    case videoFill16
    case profile16
    case safetyNumber16
    case timerDisabled16
    case timer16
    case refresh16
    case merge16

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
    case empty

    case profilePlaceholder
}

// MARK: -

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

        return image
    }

    class func iconName(_ icon: ThemeIcon) -> String {
        iconName(icon, isDarkThemeEnabled: isDarkThemeEnabled)
    }

    class func iconName(_ icon: ThemeIcon, isDarkThemeEnabled: Bool) -> String {
        switch icon {
            // App Settings
        case .settingsAccount:
            return "person-circle"
        case .settingsLinkedDevices:
            return "devices"
        case .settingsDonate:
            return "heart"
        case .settingsAppearance:
            return "appearance"
        case .settingsChats:
            return "chat"
        case .settingsStories:
            return "stories"
        case .settingsNotifications:
            return "bell"
        case .settingsPrivacy:
            return "lock"
        case .settingsDataUsage:
            return "data"
        case .settingsPayments:
            return "payment"
        case .settingsHelp:
            return "help"
        case .settingsInvite:
            return "invite"
        case .settingsAdvanced:
            return "internal"

            // Donate
        case .donateManageSubscription:
            return "person"
        case .donateBadges:
            return "badge-multi"
        case .donateGift:
            return "gift"
        case .donateReceipts:
            return "receipt"

            // Profile
        case .profileName:
            return "person"
        case .profileUsername:
            return "at"
        case .profileAbout:
            return "edit"
        case .profileBadges:
            return "badge-multi"

            // Group & Contact Info
        case .chatSettingsTimerOn:
            return "timer"
        case .chatSettingsTimerOff:
            return "timer-slash"
        case .chatSettingsWallpaper:
            return "color"
        case .chatSettingsMessageSound:
            return "speaker"
        case .chatSettingsBlock:
            return "block"
        case .chatSettingsMute:
            return "bell-slash"
        case .chatSettingsMentions:
            return "at"
        case .contactInfoSafetyNumber:
            return "safety-number"
        case .contactInfoUserInContacts:
            return "person-circle"
        case .contactInfoAddToContacts:
            return "person-circle-plus"
        case .contactInfoSignalConnection:
            return "connections"
        case .contactInfoPhone:
            return "phone"
        case .contactInfoGroups:
            return "group-resizable"
        case .groupInfoLeaveGroup:
            return "leave"
        case .groupInfoAddMembers:
            return "plus-bold"
        case .groupInfoShowAllMembers:
            return "chevron-down-bold"
        case .groupInfoGroupLink:
            return "link"
        case .groupInfoRequestAndInvites:
            return "group"
        case .groupInfoPermissions:
            return "key"
        case .groupInfoEditName:
            return "group"
        case .groupInfoEditDescription:
            return "edit"
        case .groupMemberRemoveFromGroup:
            return "minus-circle"
        case .groupMemberMakeGroupAdmin:
            return "key"
        case .groupMemberRevokeGroupAdmin:
            return "key-slash"
        case .groupMemberAddToGroup:
            return "plus-circle"

            // Generic
        case .genericGroup:
            return "group"
        case .genericStories:
            return "stories"
        case .phoneNumber:
            return "number"
        case .checkCircle:
            return "check-circle"
        case .checkCircleFill:
            return "check-circle-fill"
        case .checkmark:
            return "check"
        case .circle:
            return "circle"
        case .arrowDown:
            return "arrow-down"
        case .arrowUp:
            return "arrow-up"
        case .arrowRight:
            return "arrow-right"
        case .chevronUp:
            return "chevron-up"
        case .chevronDown:
            return "chevron-down"
        case .maximize:
            return "maximize"
        case .minimize:
            return "minimize"
        case .refresh:
            return "refresh"
        case .official:
            return isDarkThemeEnabled ? "official-dark" : "official"
        case .qrCode:
            return "qr_code"
        case .qrCodeLight:
            return "qr_code-light"

            // Buttons (24 dp)
        case .buttonCamera:
            return "camera"
        case .buttonMicrophone:
            return "mic"
        case .buttonVoiceCall:
            return "phone"
        case .buttonVideoCall:
            return "video"
        case .buttonNewCall:
            return "phone-plus"
        case .buttonMessage:
            return "chat"
        case .buttonPhotoLibrary:
            return "album-tilt"
        case .buttonCompose:
            return "compose"
        case .buttonEdit:
            return "edit"
        case .buttonMute:
            return "bell-slash"
        case .buttonDelete:
            return "trash"
        case .buttonSearch:
            return "search"
        case .buttonForward:
            return "forward"
        case .buttonShare:
            return "share"
        case .buttonSave:
            return "save"
        case .buttonCopy:
            return "copy"
        case .buttonMore:
            return "more"
        case .buttonText:
            return "text"
        case .buttonX:
            return "x"
        case .buttonRetry:
            return "refresh"
        case .buttonLink:
            return "link"

            // Context Menus (light version of icons)
        case .contextMenuSave:
            return "save-light"
        case .contextMenuDelete:
            return "trash-light"
        case .contextMenuReply:
            return "reply-light"
        case .contextMenuInfo:
            return "info-light"
        case .contextMenuCopy:
            return "copy-light"
        case .contextMenuShare:
            return "share-light"
        case .contextMenuForward:
            return "forward-light"
        case .contextMenuSelect:
            return "check-circle-light"
        case .contextMenuSpeak:
            return "speaker-light"
        case .contextMenuStopSpeaking:
            return "pause-circle-light"
        case .contextMenuSettings:
            return "settings-light"
        case .contextMenuArchive:
            return "archive-light"
        case .contextMenuEdit:
            return "edit-light"
        case .contextMenuPrivacy:
            return "lock-light"
        case .contextMenuXCircle:
            return "x-circle-light"
        case .contextMenuOpenInChat:
            return "arrow-square-upright-light"
        case .contextMenuVoiceCall:
            return "phone-light"
        case .contextMenuVideoCall:
            return "video-light"

            // Empty chat list
        case .composeNewGroupLarge:
            return "group-resizable"
        case .composeFindByPhoneNumberLarge:
            return "number-resizable"
        case .composeInviteLarge:
            return "invite-resizable"

            // Compact 16 dp icons
        case .check16:
            return "check-compact"
        case .compose16:
            return "edit-compact"
        case .error16:
            return "error-circle-compact"
        case .group16:
            return "group-compact"
        case .heart16:
            return "heart-compact"
        case .info16:
            return "info-compact"
        case .leave16:
            return "leave-compact"
        case .megaphone16:
            return "megaphone-compact"
        case .memberAdded16:
            return "person-plus-compact"
        case .memberDeclined16:
            return "person-x-compact"
        case .memberRemove16:
            return  "person-minus-compact"
        case .photo16:
            return "photo-compact"
        case .phone16:
            return "phone-compact"
        case .phoneFill16:
            return "phone-fill-compact"
        case .video16:
            return "video-compact"
        case .videoFill16:
            return "video-fill-compact"
        case .profile16:
            return "person-compact"
        case .safetyNumber16:
            return "safety-number-compact"
        case .timerDisabled16:
            return "timer-slash-compact"
        case .timer16:
            return "timer-compact"
        case .refresh16:
            return "refresh-compact"
        case .merge16:
            return "merge-compact"

        case .transfer:
            return "transfer-\(UIDevice.current.isIPad ? "ipad" : "phone")-outline-60-\(isDarkThemeEnabled ? "dark" : "light")"
        case .register:
            return "register-\(UIDevice.current.isIPad ? "ipad" : "phone")-outline-60-\(isDarkThemeEnabled ? "dark" : "light")"

        case .emojiActivity:
            return "emoji-activity"
        case .emojiAnimal:
            return "emoji-animal"
        case .emojiFlag:
            return "emoji-flag"
        case .emojiFood:
            return "emoji-food"
        case .emojiObject:
            return "emoji-object"
        case .emojiSmiley:
            return "emoji-smiley"
        case .emojiSymbol:
            return "emoji-symbol"
        case .emojiTravel:
            return "emoji-travel"
        case .emojiRecent:
            return "recent-20"
        case .emojiSettings:
            return "settings"

        case .sealedSenderIndicator:
            return "unidentified-delivery-outline-20"
        case .empty:
            return "empty-24"

        case .profilePlaceholder:
            return isDarkThemeEnabled ? "profile-placeholder-dark-56" : "profile-placeholder-56"
        }
    }
}

// MARK: -

extension Theme {

    // Bridging the old name to new name for our ObjC friends
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
