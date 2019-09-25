//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum ThemeIcon: UInt {
    case settingsAddNewContact
    case settingsAddToExistingContact
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
    case settingsShareProfile
    case settingsShowGroup
    case settingsViewSafetyNumber
    case settingsUserInContacts
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
        case .settingsAddNewContact:
            // TODO NEEDS_ASSET - waiting on design to provide an updated asset.
            return "table_ic_new_contact"
        case .settingsAddToExistingContact:
            // TODO NEEDS_ASSET - waiting on design to provide an updated asset.
            return "table_ic_add_to_existing_contact"
        case .settingsAllMedia:
            return isDarkThemeEnabled ? "photo-album-solid-24" : "photo-album-outline-24"
        case .settingsEditGroup:
            // TODO NEEDS_ASSET - waiting on design to provide an updated asset.
            return "table_ic_group_edit"
        case .settingsLeaveGroup:
            return "table_ic_group_leave"
        case .settingsViewSafetyNumber:
            return isDarkThemeEnabled ? "safety-number-solid-24" : "safety-number-outline-24"
        case .settingsProfile:
            return isDarkThemeEnabled ? "profile-circle-solid-24" : "profile-circle-outline-24"
        case .settingsShowGroup:
            return "table_ic_group_members"
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
        case .settingsShareProfile:
            // TODO NEEDS_ASSET - waiting on design to provide an updated asset.
            return "table_ic_share_profile"
        case .settingsSearch:
            return "search-24"
        case .settingsUserInContacts:
            return isDarkThemeEnabled ? "profile-circle-solid-24":  "profile-circle-outline-24"
        }
    }
}
