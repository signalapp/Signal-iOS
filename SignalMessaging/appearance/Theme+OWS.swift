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

    case stickerButton
    case cameraButton
    case micButton

    case attachmentButtonSelected
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

    case compose
    case phone
    case checkCircle
    case message
    case call
    case info
    case groupMessage
}

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

        // Input Toolbar
        case .stickerButton:
            return isDarkThemeEnabled ? "sticker-solid-24" : "sticker-outline-24"
        case .cameraButton:
            return isDarkThemeEnabled ? "camera-solid-24" : "camera-outline-24"
        case .micButton:
            return isDarkThemeEnabled ? "mic-solid-24" : "mic-outline-24"
        case .attachmentButtonSelected:
            return isDarkThemeEnabled ? "x-box-filled-28-dark" : "x-box-filled-28-light"
        case .attachmentCamera:
            return isDarkThemeEnabled ? "camera-outline-32" : "camera-outline-32-with-background"
        case .attachmentContact:
            return isDarkThemeEnabled ? "contact-outline-32" : "contact-outline-32-with-background"
        case .attachmentFile:
            return isDarkThemeEnabled ? "file-outline-32" : "file-outline-32-with-background"
        case .attachmentGif:
            return isDarkThemeEnabled ? "gif-outline-32" : "gif-outline-32-with-background"
        case .attachmentLocation:
            return isDarkThemeEnabled ? "location-outline-32" : "location-outline-32-with-background"

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

        case .compose:
            return isDarkThemeEnabled ? "compose-solid-24" : "compose-outline-24"
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
            return "group-solid-24"
        }
    }
}
