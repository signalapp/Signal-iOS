// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension Setting.EnumKey {
    /// Controls how notifications should appear for the user (See `NotificationPreviewType` for the options)
    static let preferencesNotificationPreviewType: Setting.EnumKey = "preferencesNotificationPreviewType"
    
    /// Controls what the default sound for notifications is (See `Sound` for the options)
    static let defaultNotificationSound: Setting.EnumKey = "defaultNotificationSound"
}

public extension Setting.BoolKey {
    /// Controls whether the preview screen in the app switcher should be enabled
    ///
    /// **Note:** In the legacy setting this flag controlled whether the preview was "disabled" (and defaulted to
    /// true), by inverting this flag we can default it to false as is standard for Bool values
    static let preferencesAppSwitcherPreviewEnabled: Setting.BoolKey = "preferencesAppSwitcherPreviewEnabled"
    
    /// Controls whether typing indicators are enabled
    ///
    /// **Note:** Only works if both participants in a "contact" thread have this setting enabled
    static let areReadReceiptsEnabled: Setting.BoolKey = "areReadReceiptsEnabled"
    
    /// Controls whether typing indicators are enabled
    ///
    /// **Note:** Only works if both participants in a "contact" thread have this setting enabled
    static let typingIndicatorsEnabled: Setting.BoolKey = "typingIndicatorsEnabled"
    
    /// Controls whether the message requests item has been hidden on the home screen
    static let hasHiddenMessageRequests: Setting.BoolKey = "hasHiddenMessageRequests"
}

public extension Setting.StringKey {
    /// This is the most recently recorded Push Notifications token
    static let lastRecordedPushToken: Setting.StringKey = "lastRecordedPushToken"
    
    /// This is the most recently recorded Voip token
    static let lastRecordedVoipToken: Setting.StringKey = "lastRecordedVoipToken"
}

public enum Preferences {
    public enum NotificationPreviewType: Int, EnumSetting {
        /// Notifications should include both the sender name and a preview of the message content
        case nameAndPreview
        
        /// Notifications should include the sender name but no preview
        case nameNoPreview
        
        /// Notifications should be a generic message
        case noNameNoPreview
        
        var name: String {
            switch self {
                case .nameAndPreview: return "NOTIFICATIONS_SENDER_AND_MESSAGE".localized()
                case .nameNoPreview: return "NOTIFICATIONS_SENDER_ONLY".localized()
                case .noNameNoPreview: return "NOTIFICATIONS_NONE".localized()
            }
        }
        
        var accessibilityIdentifier: String {
            return "NotificationSettingsOptionsViewController.\(name)"
        }
    }
    
    public enum Sound: Int, Codable, DatabaseValueConvertible, EnumSetting {
        static var defaultiOSIncomingRingtone: Sound = .opening
        static var defaultNotificationSound: Sound = .note
        
        case `default`
        
        // Notification Sounds
        case aurora = 1000
        case bamboo
        case chord
        case circles
        case complete
        case hello
        case input
        case keys
        case note
        case popcorn
        case pulse
        case synth
        case signalClassic
        
        // Ringtone Sounds
        case opening = 2000
        
        // Calls
        case callConnecting = 3000
        case callOutboundRinging
        case callBusy
        case callFailure
        
        // Other
        case messageSent = 4000
        case none
        
        static var notificationSounds: [Sound] {
            return [
                // None and Note (default) should be first.
                .none,
                .note,
                
                .aurora,
                .bamboo,
                .chord,
                .circles,
                .complete,
                .hello,
                .input,
                .keys,
                .popcorn,
                .pulse,
                .synth
            ]
        }
    }
}
