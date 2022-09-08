// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import AudioToolbox
import GRDB
import DifferenceKit
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
    static let appSwitcherPreviewEnabled: Setting.BoolKey = "appSwitcherPreviewEnabled"
    
    /// Controls whether typing indicators are enabled
    ///
    /// **Note:** Only works if both participants in a "contact" thread have this setting enabled
    static let areReadReceiptsEnabled: Setting.BoolKey = "areReadReceiptsEnabled"
    
    /// Controls whether typing indicators are enabled
    ///
    /// **Note:** Only works if both participants in a "contact" thread have this setting enabled
    static let typingIndicatorsEnabled: Setting.BoolKey = "typingIndicatorsEnabled"
    
    /// Controls whether the device will automatically lock the screen
    static let isScreenLockEnabled: Setting.BoolKey = "isScreenLockEnabled"
    
    /// Controls whether Link Previews (image & title URL metadata) will be downloaded when the user enters a URL
    ///
    /// **Note:** Link Previews are only enabled for HTTPS urls
    static let areLinkPreviewsEnabled: Setting.BoolKey = "areLinkPreviewsEnabled"
    
    /// Controls whether Calls are enabled
    static let areCallsEnabled: Setting.BoolKey = "areCallsEnabled"
    
    /// Controls whether open group messages older than 6 months should be deleted
    static let trimOpenGroupMessagesOlderThanSixMonths: Setting.BoolKey = "trimOpenGroupMessagesOlderThanSixMonths"
    
    /// Controls whether the message requests item has been hidden on the home screen
    static let hasHiddenMessageRequests: Setting.BoolKey = "hasHiddenMessageRequests"
    
    /// Controls whether the notification sound should play while the app is in the foreground
    static let playNotificationSoundInForeground: Setting.BoolKey = "playNotificationSoundInForeground"
    
    /// A flag indicating whether the user has ever viewed their seed
    static let hasViewedSeed: Setting.BoolKey = "hasViewedSeed"
    
    /// A flag indicating whether the user has ever saved a thread
    static let hasSavedThread: Setting.BoolKey = "hasSavedThread"
    
    /// A flag indicating whether the user has ever send a message
    static let hasSentAMessage: Setting.BoolKey = "hasSentAMessageKey"
    
    /// A flag indicating whether the app is ready for app extensions to run
    static let isReadyForAppExtensions: Setting.BoolKey = "isReadyForAppExtensions"
    
    /// Controls whether the device should show screenshot notifications in one-to-one conversations (will always
    /// send screenshot notifications, this just controls whether they get filtered out or not)
    static let showScreenshotNotifications: Setting.BoolKey = "showScreenshotNotifications"
    
    /// Controls whether concurrent audio messages should automatically be played after the one the user starts
    /// playing finishes
    static let shouldAutoPlayConsecutiveAudioMessages: Setting.BoolKey = "shouldAutoPlayConsecutiveAudioMessages"
}

public extension Setting.StringKey {
    /// This is the most recently recorded Push Notifications token
    static let lastRecordedPushToken: Setting.StringKey = "lastRecordedPushToken"
    
    /// This is the most recently recorded Voip token
    static let lastRecordedVoipToken: Setting.StringKey = "lastRecordedVoipToken"
    
    /// This is the last six emoji used by the user
    static let recentReactionEmoji: Setting.StringKey = "recentReactionEmoji"
    
    /// This is the preferred skin tones preference for the given emoji
    static func emojiPreferredSkinTones(emoji: String) -> Setting.StringKey {
        return Setting.StringKey("preferredSkinTones-\(emoji)")
    }
}

public extension Setting.DoubleKey {
    /// The duration of the timeout for screen lock in seconds
    @available(*, unavailable, message: "Screen Lock should always be instant now")
    static let screenLockTimeoutSeconds: Setting.DoubleKey = "screenLockTimeoutSeconds"
}

public enum Preferences {
    public enum NotificationPreviewType: Int, CaseIterable, EnumIntSetting, Differentiable {
        public static var defaultPreviewType: NotificationPreviewType = .nameAndPreview
        
        /// Notifications should include both the sender name and a preview of the message content
        case nameAndPreview
        
        /// Notifications should include the sender name but no preview
        case nameNoPreview
        
        /// Notifications should be a generic message
        case noNameNoPreview
        
        public var name: String {
            switch self {
                case .nameAndPreview: return "NOTIFICATIONS_SENDER_AND_MESSAGE".localized()
                case .nameNoPreview: return "NOTIFICATIONS_SENDER_ONLY".localized()
                case .noNameNoPreview: return "NOTIFICATIONS_NONE".localized()
            }
        }
    }
    
    public enum Sound: Int, Codable, DatabaseValueConvertible, EnumIntSetting, Differentiable {
        public static var defaultiOSIncomingRingtone: Sound = .opening
        public static var defaultNotificationSound: Sound = .note
        
        // Don't store too many sounds in memory (Most users will only use 1 or 2 sounds anyway)
        private static let maxCachedSounds: Int = 4
        private static var cachedSystemSounds: Atomic<[String: (url: URL?, soundId: SystemSoundID)]> = Atomic([:])
        private static var cachedSystemSoundOrder: Atomic<[String]> = Atomic([])
        
        // Values
        
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
        
        public static var notificationSounds: [Sound] {
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
        
        public var displayName: String {
            // TODO: Should we localize these sound names?
            switch self {
                case .`default`: return ""
                
                // Notification Sounds
                case .aurora: return "Aurora"
                case .bamboo: return "Bamboo"
                case .chord: return "Chord"
                case .circles: return "Circles"
                case .complete: return "Complete"
                case .hello: return "Hello"
                case .input: return "Input"
                case .keys: return "Keys"
                case .note: return "Note"
                case .popcorn: return "Popcorn"
                case .pulse: return "Pulse"
                case .synth: return "Synth"
                case .signalClassic: return "Signal Classic"
                
                // Ringtone Sounds
                case .opening: return "Opening"
                
                // Calls
                case .callConnecting: return "Call Connecting"
                case .callOutboundRinging: return "Call Outboung Ringing"
                case .callBusy: return "Call Busy"
                case .callFailure: return "Call Failure"
                
                // Other
                case .messageSent: return "Message Sent"
                case .none: return "SOUNDS_NONE".localized()
            }
        }
        
        // MARK: - Functions
        
        public func filename(quiet: Bool = false) -> String? {
            switch self {
                case .`default`: return ""
                
                // Notification Sounds
                case .aurora: return (quiet ? "aurora-quiet.aifc" : "aurora.aifc")
                case .bamboo: return (quiet ? "bamboo-quiet.aifc" : "bamboo.aifc")
                case .chord: return (quiet ? "chord-quiet.aifc" : "chord.aifc")
                case .circles: return (quiet ? "circles-quiet.aifc" : "circles.aifc")
                case .complete: return (quiet ? "complete-quiet.aifc" : "complete.aifc")
                case .hello: return (quiet ? "hello-quiet.aifc" : "hello.aifc")
                case .input: return (quiet ? "input-quiet.aifc" : "input.aifc")
                case .keys: return (quiet ? "keys-quiet.aifc" : "keys.aifc")
                case .note: return (quiet ? "note-quiet.aifc" : "note.aifc")
                case .popcorn: return (quiet ? "popcorn-quiet.aifc" : "popcorn.aifc")
                case .pulse: return (quiet ? "pulse-quiet.aifc" : "pulse.aifc")
                case .synth: return (quiet ? "synth-quiet.aifc" : "synth.aifc")
                case .signalClassic: return (quiet ? "classic-quiet.aifc" : "classic.aifc")
                
                // Ringtone Sounds
                case .opening: return "Opening.m4r"
                
                // Calls
                case .callConnecting: return "ringback_tone_ansi.caf"
                case .callOutboundRinging: return "ringback_tone_ansi.caf"
                case .callBusy: return "busy_tone_ansi.caf"
                case .callFailure: return "end_call_tone_cept.caf"
                
                // Other
                case .messageSent: return "message_sent.aiff"
                case .none: return nil
            }
        }
        
        public func soundUrl(quiet: Bool = false) -> URL? {
            guard let filename: String = filename(quiet: quiet) else { return nil }
            
            let url: URL = URL(fileURLWithPath: filename)
            
            return Bundle.main.url(
                forResource: url.deletingPathExtension().path,
                withExtension: url.pathExtension
            )
        }
        
        public func notificationSound(isQuiet: Bool) -> UNNotificationSound {
            guard let filename: String = filename(quiet: isQuiet) else {
                SNLog("[Preferences.Sound] filename was unexpectedly nil")
                return UNNotificationSound.default
            }
            
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
        }
        
        public static func systemSoundId(for sound: Sound, quiet: Bool) -> SystemSoundID {
            let cacheKey: String = "\(sound.rawValue):\(quiet ? 1 : 0)"
            
            if let cachedSound: SystemSoundID = cachedSystemSounds.wrappedValue[cacheKey]?.soundId {
                return cachedSound
            }
            
            let systemSound: (url: URL?, soundId: SystemSoundID) = (
                url: sound.soundUrl(quiet: quiet),
                soundId: SystemSoundID()
            )
            
            cachedSystemSounds.mutate { cache in
                cachedSystemSoundOrder.mutate { order in
                    if order.count > Sound.maxCachedSounds {
                        cache.removeValue(forKey: order[0])
                        order.remove(at: 0)
                    }
                    
                    order.append(cacheKey)
                }
                
                cache[cacheKey] = systemSound
            }
            
            return systemSound.soundId
        }
        
        // MARK: - AudioPlayer
        
        public static func audioPlayer(for sound: Sound, behavior: OWSAudioBehavior) -> OWSAudioPlayer? {
            guard let soundUrl: URL = sound.soundUrl(quiet: false) else { return nil }
            
            let player = OWSAudioPlayer(mediaUrl: soundUrl, audioBehavior: behavior)
            
            // These two cases should loop
            if sound == .callConnecting || sound == .callOutboundRinging {
                player.isLooping = true
            }
            
            return player
        }
    }
    
    public static var isCallKitSupported: Bool {
        guard let regionCode: String = NSLocale.current.regionCode else { return false }
        guard !regionCode.contains("CN") && !regionCode.contains("CHN") else { return false }
        
        return true
    }
}
