//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

enum FeatureBuild: Int, Comparable {
    case dev
    case `internal`
    case beta
    case production

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

private let build = FeatureBuild.current

// MARK: -

/// By centralizing feature flags here and documenting their rollout plan,
/// it's easier to review which feature flags are in play.
public enum BuildFlags {

    public static let choochoo = build <= .internal

    public static let failDebug = build <= .internal

    public static let linkedPhones = build <= .internal

    public static let isPrerelease = build <= .beta

    public static let shouldUseTestIntervals = build <= .beta

    /// If we ever need to internally detect database corruption again in the
    /// future, we can re-enable this.
    public static let periodicallyCheckDatabaseIntegrity: Bool = false

    public enum Backups {
        public static let showMegaphones = build <= .internal
        public static let showOptimizeMedia = build <= .dev

        public static let restoreFailOnAnyError = build <= .beta
        public static let detailedBenchLogging = build <= .internal
        public static let errorDisplay = build <= .internal

        public static let avoidAppAttestForDevs = build <= .dev
        public static let avoidStoreKitForTesters = build <= .beta

        public static let useLowerDefaultListMediaRefreshInterval = build <= .beta
        public static let performListMediaIntegrityChecks = build <= .beta
    }

    public static let runTSAttachmentMigrationInMainAppBackground = true
    public static let runTSAttachmentMigrationBlockingOnLaunch = true

    /// We are still making Xcode 16 builds as of writing this, and some iOS 26
    /// changes must only be applied if the SDK is also iOS 26.
#if compiler(>=6.2)
    public static let iOS26SDKIsAvailable = true
#else
    public static let iOS26SDKIsAvailable = false
#endif

    public static let pollSend = true
    public static let pollReceive = true

    static let netBuildVariant: Net.BuildVariant = build <= .beta ? .beta : .production

    // Turn this off after all still-registered clients have run this
    // migration. That should happen by 2026-05-27. Then, delete all the code
    // that's now dead because this is false.
    public static let decodeDeprecatedPreKeys = true

    public static let serviceIdBinaryProvisioning = true
    public static let serviceIdBinaryConstantOverhead = !serviceIdStrings || (build <= .internal)
    public static let serviceIdBinaryVariableOverhead = !serviceIdStrings || (build <= .dev)
    public static let serviceIdBinaryOneOf = !serviceIdStrings

    public static let serviceIdStrings = TSConstants.isUsingProductionService

    public enum PinnedMessages {
        public static let send = build <= .dev
        public static let receive = build <= .dev
    }

    public static let useNewAttachmentLimits = false
}

// MARK: -
@objc
public class BuildFlagsObjC: NSObject {
    @objc
    public static let serviceIdBinaryConstantOverhead = BuildFlags.serviceIdBinaryConstantOverhead

    @objc
    public static let serviceIdBinaryVariableOverhead = BuildFlags.serviceIdBinaryVariableOverhead

    @objc
    public static let serviceIdStrings = BuildFlags.serviceIdStrings
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

    public static let audibleErrorLogging = build <= .internal

    public static let internalSettings = build <= .internal

    public static let internalMegaphoneEligible = build <= .internal

    public static let verboseNotificationLogging = build <= .internal

    public static let deviceTransferVerboseProgressLogging = build <= .internal

    public static let messageDetailsExtraInfo = build <= .internal

    public static let exposeCensorshipCircumvention = build <= .internal

    public static let extraDebugLogs = build <= .internal

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
        guard build <= .internal else {
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
