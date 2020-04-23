//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
    case settingsViewPendingInvites

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

    case compose
    case composeNewGroup
    case composeFindByPhoneNumber
    case composeInvite

    case phone
    case checkCircle
    case message
    case call
    case info
    case groupMessage
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
            return isDarkThemeEnabled ? "contact-solid-24" : "contact-outline-24"
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
            return isDarkThemeEnabled ? "profile-circle-solid-24" : "profile-circle-outline-24"
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
        case .settingsViewPendingInvites:
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
            return "plus-24"
        case .settingsShowAllMembers:
            return "ic_chevron_down"

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

        case .compose:
            return isDarkThemeEnabled ? "compose-solid-24" : "compose-outline-24"
        case .composeNewGroup:
            return "group-outline-32"
        case .composeFindByPhoneNumber:
            return "phone-number-32"
        case .composeInvite:
            return "invite-outline-32"

        case .phone:
            return isDarkThemeEnabled ? "button_phone_white" : "phone-right-outline-24"
        case .checkCircle:
            return isDarkThemeEnabled ? "check-circle-solid-24" : "check-circle-outline-24"
        case .message:
            return isDarkThemeEnabled ? "message-solid-24" : "message-outline-24"
        case .call:
            return isDarkThemeEnabled ? "button_phone_white" : "phone-right-outline-24"
        case .info:
            return isDarkThemeEnabled ? "info-solid-24" : "ic_info"
        case .groupMessage:
            return "group-outline-20"
        }
    }
}
