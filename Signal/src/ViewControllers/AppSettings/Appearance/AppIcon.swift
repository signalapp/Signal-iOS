//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

extension UIApplication {
    var currentAppIcon: AppIcon {
        if let alternateIconName, let appIcon = AppIcon(alternateIconName: alternateIconName) {
            return appIcon
        }
        return .default
    }
}

enum AppIcon: String {
    case `default` = "AppIcon"
    case white = "AppIcon-white"
    case color = "AppIcon-color"
    case night = "AppIcon-dark"
    case nightVariant = "AppIcon-dark-variant"
    case chat = "AppIcon-chat"
    case bubbles = "AppIcon-bubbles"
    case yellow = "AppIcon-yellow"
    case news = "AppIcon-news"
    case notes = "AppIcon-notes"
    case weather = "AppIcon-weather"
    case waves = "AppIcon-wave"

    init?(alternateIconName: String) {
        if let asset = AppIcon(rawValue: alternateIconName) {
            self = asset
        } else {
            owsFailDebug("Unknown alternative app icon name '\(alternateIconName)'")
            return nil
        }
    }

    var alternateIconName: String? {
        if case .default = self {
            nil
        } else {
            rawValue
        }
    }

    var previewImageResource: ImageResource {
        switch self {
        case .default: ImageResource.AppIconPreview.default
        case .white: ImageResource.AppIconPreview.white
        case .color: ImageResource.AppIconPreview.color
        case .night: ImageResource.AppIconPreview.dark
        case .nightVariant: ImageResource.AppIconPreview.darkVariant
        case .chat: ImageResource.AppIconPreview.chat
        case .bubbles: ImageResource.AppIconPreview.bubbles
        case .yellow: ImageResource.AppIconPreview.yellow
        case .news: ImageResource.AppIconPreview.news
        case .notes: ImageResource.AppIconPreview.notes
        case .weather: ImageResource.AppIconPreview.weather
        case .waves: ImageResource.AppIconPreview.wave
        }
    }

    /// Indicates if the icon should be rendered with a shadow in the picker.
    ///
    /// Some icons have a white background and should show a subtle
    /// shadow in the picker to separate it from the background.
    var shouldShowShadow: Bool {
        switch self {
        case .white, .bubbles:
            true
        default:
            false
        }
    }
}
