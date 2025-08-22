//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum FeatureBuild: Int {
    case dev
    case `internal`
    case beta
    case production
}

private extension FeatureBuild {
    func includes(_ level: FeatureBuild) -> Bool {
        return self.rawValue <= level.rawValue
    }
}

private let build = FeatureBuild.current

// MARK: -

/// By centralizing feature flags here and documenting their rollout plan,
/// it's easier to review which feature flags are in play.
public enum FeatureFlags {

    public static let choochoo = build.includes(.internal)

    public static let failDebug = build.includes(.internal)

    public static let linkedPhones = build.includes(.internal)

    public static let preRegDeviceTransfer = build.includes(.dev)

    public static let isPrerelease = build.includes(.beta)

    public static let shouldUseTestIntervals = build.includes(.beta)

    /// If we ever need to internally detect database corruption again in the
    /// future, we can re-enable this.
    public static let periodicallyCheckDatabaseIntegrity: Bool = false

    public enum Backups {
        public static let supported = build.includes(.internal)
        public static let showSettings = build.includes(.dev)

        public static let restoreFailOnAnyError = build.includes(.beta)
        public static let detailedBenchLogging = build.includes(.internal)
        public static let errorDisplay = build.includes(.internal)

        public static let avoidAppAttestForDevs = build.includes(.dev)
        public static let avoidStoreKitForTesters = build.includes(.beta)
    }

    public static let runTSAttachmentMigrationInMainAppBackground = true
    public static let runTSAttachmentMigrationBlockingOnLaunch = true

    public static let useNewConversationLoadIndex = true

    public static let libsignalEnforceMinTlsVersion = false

    public static let moveDraftsUpChatList = true

    public static let postRegWebSocket = false

    /// We are still making Xcode 16 builds as of writing this, and some iOS 26
    /// changes must only be applied if the SDK is also iOS 26.
#if compiler(>=6.2)
    public static let iOS26SDKIsAvailable = true
#else
    public static let iOS26SDKIsAvailable = false
#endif
}

// MARK: -

extension FeatureFlags {
    public static var buildVariantString: String? {
        // Leaving this internal only for now. If we ever move this to
        // HelpSettings we need to localize these strings
        guard DebugFlags.internalSettings else {
            owsFailDebug("Incomplete implementation. Needs localization")
            return nil
        }

        let featureFlagString: String?
        switch build {
        case .dev:
            featureFlagString = LocalizationNotNeeded("Dev")
        case .internal:
            featureFlagString = LocalizationNotNeeded("Internal")
        case .beta:
            featureFlagString = LocalizationNotNeeded("Beta")
        case .production:
            // Production can be inferred from the lack of flag
            featureFlagString = nil
        }

        let configuration: String? = {
            #if DEBUG
            LocalizationNotNeeded("Debug")
            #elseif TESTABLE_BUILD
            LocalizationNotNeeded("Testable")
            #else
            // RELEASE can be inferred from the lack of configuration. This will only be hit if the outer #if is removed.
            nil
            #endif
        }()

        // If we're Production+Release, this will return nil and won't show up in Help Settings
        return [featureFlagString, configuration]
            .compactMap { $0 }
            .joined(separator: " — ")
            .nilIfEmpty
    }
}

// MARK: -

/// Flags that we'll leave in the code base indefinitely that are helpful for
/// development should go here, rather than cluttering up FeatureFlags.
public enum DebugFlags {
    public static let internalLogging = build.includes(.internal)

    public static let betaLogging = build.includes(.beta)

    public static let testPopulationErrorAlerts = build.includes(.beta)

    public static let audibleErrorLogging = build.includes(.internal)

    public static let internalSettings = build.includes(.internal)

    public static let internalMegaphoneEligible = build.includes(.internal)

    public static let verboseNotificationLogging = build.includes(.internal)

    public static let deviceTransferVerboseProgressLogging = build.includes(.internal)

    public static let messageDetailsExtraInfo = build.includes(.internal)

    public static let exposeCensorshipCircumvention = build.includes(.internal)

    public static let extraDebugLogs = build.includes(.internal)

    public static let messageSendsFail = TestableFlag(
        false,
        title: LocalizationNotNeeded("Message Sends Fail"),
        details: LocalizationNotNeeded("All outgoing message sends will fail.")
    )

    public static let callingUseTestSFU = TestableFlag(
        false,
        title: LocalizationNotNeeded("Calling: Use Test SFU"),
        details: LocalizationNotNeeded("Group calls will connect to sfu.test.voip.signal.org.")
    )

    public static let delayedMessageResend = TestableFlag(
        false,
        title: LocalizationNotNeeded("Delayed message resend"),
        details: LocalizationNotNeeded("Waits 10s before responding to a resend request.")
    )

    public static let fastPlaceholderExpiration = TestableFlag(
        false,
        title: LocalizationNotNeeded("Early placeholder expiration"),
        details: LocalizationNotNeeded("Shortens the valid window for message resend+recovery."),
        toggleHandler: { _ in
            SSKEnvironment.shared.messageDecrypterRef.cleanUpExpiredPlaceholders()
        }
    )

    public static func allTestableFlags() -> [TestableFlag] {
        return [
            callingUseTestSFU,
            delayedMessageResend,
            fastPlaceholderExpiration,
            messageSendsFail,
        ]
    }
}

// MARK: -

public class TestableFlag {
    private let defaultValue: Bool
    private let flag: AtomicBool
    public let title: String
    public let details: String
    public let toggleHandler: ((Bool) -> Void)?

    fileprivate init(_ defaultValue: Bool,
                     title: String,
                     details: String,
                     toggleHandler: ((Bool) -> Void)? = nil) {
        self.defaultValue = defaultValue
        self.title = title
        self.details = details
        self.flag = AtomicBool(defaultValue, lock: .sharedGlobal)
        self.toggleHandler = toggleHandler

        // Normally we'd store the observer here and remove it in deinit.
        // But TestableFlags are always static; they don't *get* deinitialized except in testing.
        NotificationCenter.default.addObserver(forName: Self.ResetAllTestableFlagsNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.set(self.defaultValue)
        }
    }

    public func get() -> Bool {
        guard build.includes(.internal) else {
            return defaultValue
        }
        return flag.get()
    }

    public func set(_ value: Bool) {
        flag.set(value)

        toggleHandler?(value)
    }

    @objc
    private func switchDidChange(_ sender: UISwitch) {
        set(sender.isOn)
    }

    public var switchSelector: Selector { #selector(switchDidChange(_:)) }

    public static let ResetAllTestableFlagsNotification = NSNotification.Name("ResetAllTestableFlags")
}
