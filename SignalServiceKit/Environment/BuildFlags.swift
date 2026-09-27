//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
import LibSignalClient

enum FeatureBuild: Int, Comparable {
    case dev
    case `internal`
    case beta
    case production

    static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

private let build = FeatureBuild.current

// MARK: -

/// By centralizing feature flags here and documenting their rollout plan,
/// it's easier to review which feature flags are in play.
public enum BuildFlags {

    public static let failDebug = build <= .internal

    public static let isPrerelease = build <= .beta

    public static let shouldUseTestIntervals = build <= .beta

    public enum Backups {
        public static let showOptimizeMedia = build <= .dev

        public static let restoreFailOnAnyError = build <= .beta
        public static let detailedBenchLogging = build <= .internal
        public static let archiveErrorDisplay = build <= .internal

        public static let avoidAppAttestForDevs = build <= .dev
        public static let avoidStoreKitForTesters = build <= .beta

        public static let mediaErrorDisplay = build <= .beta
        public static let useLowerDefaultListMediaRefreshInterval = build <= .beta
    }

    static let netBuildVariant: Net.BuildVariant = build <= .beta ? .beta : .production

    // Turn this off after all still-registered clients have run this
    // migration. That should happen about 210 days after the last release
    // without this change is built. Then, delete all the code that's now dead
    // because this is false.
    public static let migrateHasPaymentAddress = true

    // Turn this off 14 days after the last release without this change
    // expires. Then, delete all the code that's now dead.
    public static let decodeOldSenderKeys = true

    // Turn this off 7 days after the last release without this change expires.
    // Then, delete all the code that's now dead.
    public static let migrateGroupRefreshedAt = true

    public enum KeyTransparency {
        public static let conservativeSelfCheck = build <= .internal
    }

    public static let wifiAwareDeviceTransfer = true

    public enum ReleaseNotesChannel {
        public static let ignoreFetchDelay = build <= .internal
    }

    public enum LocalFileBackups {
        public static let archive = true
        public static let restore = true
        public static let settingsUI = true
    }

    static let hardDeleteGroupThreadsDuringRefresh = true

    /// New notification settings. Don't enable until Storage Service is integrated
    public static let improvedNotifications = build <= .dev

    /// The ability to share account identifiers when sharing contacts.
    public static let accountIdentifierSharing = false
}

// MARK: -

extension BuildFlags {
    public static var buildVariantString: String? {
        // Leaving this internal only for now. If we ever move this to
        // HelpSettings we need to localize these strings
        guard DebugFlags.internalSettings else {
            owsFailDebug("Incomplete implementation. Needs localization")
            return nil
        }

        let buildFlagString: String?
        switch build {
        case .dev:
            buildFlagString = LocalizationNotNeeded("Dev")
        case .internal:
            buildFlagString = LocalizationNotNeeded("Internal")
        case .beta:
            buildFlagString = LocalizationNotNeeded("Beta")
        case .production:
            // Production can be inferred from the lack of flag
            buildFlagString = nil
        }

        let configuration: String? = {
#if DEBUG
            LocalizationNotNeeded("Debug")
#elseif TESTABLE_BUILD
            LocalizationNotNeeded("Testable")
#else
            // RELEASE can be inferred from the lack of configuration.
            nil
#endif
        }()

        return [buildFlagString, configuration]
            .compactMap { $0 }
            .joined(separator: " — ")
            .nilIfEmpty
    }
}

// MARK: -

/// Flags that we'll leave in the code base indefinitely that are helpful for
/// development should go here, rather than cluttering up BuildFlags.
public enum DebugFlags {
    public static let internalLogging = build <= .internal

    public static let betaLogging = build <= .beta

    public static let testPopulationErrorAlerts = build <= .beta

    public static let internalSettings = build <= .internal

    public static let internalMegaphoneEligible = build <= .internal

    public static let verboseNotificationLogging = build <= .internal

    public static let deviceTransferVerboseProgressLogging = build <= .internal

    public static let messageDetailsExtraInfo = build <= .internal

    public static let exposeCensorshipCircumvention = build <= .internal

    public static let extraDebugLogs = build <= .internal

    // MARK: - TestableFlag: Calling

    public static let callingSvcMaxBitrateBps = TestableFlag<Int>(
        0,
        title: LocalizationNotNeeded("SVC Maximum Bitrate (bps)"),
        details: LocalizationNotNeeded("The bitrate to use for new calls (overrides remote config). 0 = use default bitrate."),
    )

    public static let callingStatsIntervalSecs = TestableFlag<Int>(
        0,
        title: LocalizationNotNeeded("Stats Interval (secs)"),
        details: LocalizationNotNeeded("The interval in seconds between logging call stats. 0 = use default interval."),
    )

    public static let callingUseTestSFU = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Use Test SFU"),
        details: LocalizationNotNeeded("Group calls will connect to sfu.test.voip.signal.org."),
    )

    public static let callingNeverRelay = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Never use relay"),
        details: LocalizationNotNeeded("1:1 calls will not connect to a TURN server (remote party may still use TURN)."),
    )

    public static let callingOverrideCodecs = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Use codec overrides below"),
        details: LocalizationNotNeeded("Must be enabled to use the codec overrides below."),
    )

    public static let callingEnableVp9Encode = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Enable VP9 Encode"),
        details: LocalizationNotNeeded("Calls will offer VP9 encode (overrides remote config)."),
    )

    public static let callingEnableVp9Decode = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Enable VP9 Decode"),
        details: LocalizationNotNeeded("Calls will offer VP9 decode (overrides remote config)."),
    )

    public static let callingEnableSvc = TestableFlag(
        false,
        title: LocalizationNotNeeded("Enable SVC"),
        details: LocalizationNotNeeded("Group calls will always use SVC (overrides remote config)"),
    )

    public static let callingTestableFlags: [AnyTestableFlag] = [
        callingUseTestSFU,
        callingStatsIntervalSecs,
        callingNeverRelay,
        callingOverrideCodecs,
        callingEnableVp9Encode,
        callingEnableVp9Decode,
        callingEnableSvc,
        callingSvcMaxBitrateBps,
    ]

    // MARK: - TestableFlag: Messaging

    public static let delayedMessageResend = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Delayed message resend"),
        details: LocalizationNotNeeded("Waits 10s before responding to a resend request."),
    )

    public static let fastPlaceholderExpiration = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Early placeholder expiration"),
        details: LocalizationNotNeeded("Shortens the valid window for message resend+recovery."),
        onSet: { _ in
            DependenciesBridge.shared.decryptionPlaceholderExpirationJob.restart()
        },
    )

    public static let messageSendsFail = TestableFlag<Bool>(
        false,
        title: LocalizationNotNeeded("Message Sends Fail"),
        details: LocalizationNotNeeded("All outgoing message sends will fail."),
    )

    public static let messagingTestableFlags: [AnyTestableFlag] = [
        delayedMessageResend,
        fastPlaceholderExpiration,
        messageSendsFail,
    ]

    // MARK: - TestableFlag: Voice Messages

    public static let voiceMessageBitRate = TestableFlag<Int>(
        32000,
        title: LocalizationNotNeeded("Bitrate"),
        details: LocalizationNotNeeded("The bitrate to use for new voice message recordings."),
    )

    public static let voiceMessageSampleRate = TestableFlag<Int>(
        44100,
        title: LocalizationNotNeeded("Sample Rate"),
        details: LocalizationNotNeeded("The sample rate to use for new voice message recordings."),
    )

    public enum VoiceMessageAudioQuality: CaseIterable {
        case min
        case low
        case medium
        case high
        case max

        public var avAudioQuality: AVAudioQuality {
            switch self {
            case .min: .min
            case .low: .low
            case .medium: .medium
            case .high: .high
            case .max: .max
            }
        }
    }

    public static let voiceMessageAudioQuality = MenuTestableFlag<VoiceMessageAudioQuality>(
        nil,
        title: LocalizationNotNeeded("Audio Quality"),
        details: LocalizationNotNeeded("The encoder audio quality to use for new voice message recordings."),
    )

    public static let voiceMessageTestableFlags: [AnyTestableFlag] = [
        voiceMessageBitRate,
        voiceMessageSampleRate,
        voiceMessageAudioQuality,
    ]
}

// MARK: -

extension Notification.Name {
    public static let resetAllTestableFlags = Notification.Name("ResetAllTestableFlags")
}

/// A type-erased `TestableFlag`, for heterogenous collections.
public protocol AnyTestableFlag {
    var title: String { get }
    var details: String { get }
}

public class TestableFlag<Value>: AnyTestableFlag {
    public let title: String
    public let details: String

    private let defaultValue: Value
    private let flag: AtomicValue<Value>
    private let onSet: (Value) -> Void

    fileprivate init(
        _ defaultValue: Value,
        title: String,
        details: String,
        onSet: @escaping (Value) -> Void = { _ in },
    ) {
        self.defaultValue = defaultValue
        self.title = title
        self.details = details
        self.flag = AtomicValue(defaultValue, lock: .init())
        self.onSet = onSet

        // Normally we'd store the observer here and remove it in deinit.
        // But TestableFlags are always static; they don't *get* deinitialized except in testing.
        NotificationCenter.default.addObserver(
            forName: .resetAllTestableFlags,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            guard let self else { return }
            set(defaultValue)
        }
    }

    public func get() -> Value {
        guard build <= .internal else {
            return defaultValue
        }

        return flag.get()
    }

    public func set(_ value: Value) {
        flag.update {
            $0 = value
            onSet(value)
        }
    }
}

// MARK: -

public struct MenuTestableFlagOption {
    public let title: String
    public let isSelected: Bool
    public let select: () -> Void
}

/// See `AnyTestableFlag`.
public protocol AnyMenuTestableFlag: AnyTestableFlag {
    var menuOptions: [MenuTestableFlagOption] { get }
}

/// A `TestableFlag` whose discrete options are presented in a menu.
public class MenuTestableFlag<Value: CaseIterable & Equatable>:
    TestableFlag<Value?>,
    AnyMenuTestableFlag
{
    public var menuOptions: [MenuTestableFlagOption] {
        let selectedValue = get()

        let nilOption = MenuTestableFlagOption(
            title: "unset",
            isSelected: selectedValue == nil,
            select: { [weak self] in
                self?.set(nil)
            },
        )

        return [nilOption] + Value.allCases.map { value in
            MenuTestableFlagOption(
                title: String(describing: value),
                isSelected: selectedValue == value,
                select: { [weak self] in
                    self?.set(value)
                },
            )
        }
    }
}
