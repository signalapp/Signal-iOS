//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private enum FeatureBuild: Int {
    case dev
    case internalPreview
    case `internal`
    case openPreview
    case beta
    case production
}

extension FeatureBuild {
    func includes(_ level: FeatureBuild) -> Bool {
        return self.rawValue <= level.rawValue
    }
}

private let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .internal

// MARK: -

@objc
public enum StorageMode: Int {
    // Use GRDB.
    case grdb
    // These modes can be used while running tests.
    // They are more permissive than the release modes.
    //
    // The build shepherd should be running the test
    // suites in .grdbTests mode before each release.
    case grdbTests
}

// MARK: -

extension StorageMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .grdb:
            return ".grdb"
        case .grdbTests:
            return ".grdbTests"
        }
    }
}

// MARK: -

/// By centralizing feature flags here and documenting their rollout plan, it's easier to review
/// which feature flags are in play.
@objc(SSKFeatureFlags)
public class FeatureFlags: BaseFlags {

    public static let choochoo = build.includes(.internal)

    @objc
    public static let phoneNumberSharing = build.includes(.internal)

    @objc
    public static let phoneNumberDiscoverability = build.includes(.internal)

    @objc
    public static let phoneNumberIdentifiers = false

    @objc
    public static let usernames = build.includes(.internal)

    @objc
    public static let linkedPhones = build.includes(.internal)

    public static let preRegDeviceTransfer = build.includes(.dev)

    // We keep this feature flag around as we may want to
    // ship a build that disables the dependency on KBS
    // during registration. Features cannot be toggled
    // remotely during registration.
    @objc
    public static let pinsForNewUsers = true

    @objc
    public static let supportAnimatedStickers_Lottie = false

    @objc
    public static let paymentsScrubDetails = false

    @objc
    public static let deprecateREST = false

    public static let isPrerelease = build.includes(.beta)

    @objc
    public static var notificationServiceExtension: Bool {
        // The CallKit APIs for the NSE are only available from iOS 14.5 and on,
        // however there is a significant bug in iOS 14 where the NSE will not
        // launch properly after a crash so we only support it in iOS 15.
        if #available(iOS 15, *) { return true }
        return false
    }

    public static let periodicallyCheckDatabaseIntegrity: Bool = build.includes(.internal)

    @objc
    public static func logFlags() {
        let logFlag = { (prefix: String, key: String, value: Any?) in
            if let value = value {
                Logger.info("\(prefix): \(key) = \(value)", function: "")
            } else {
                Logger.info("\(prefix): \(key) = nil", function: "")
            }
        }

        let flagMap = allFlags()
        for key in flagMap.keys.sorted() {
            let value = flagMap[key]
            logFlag("FeatureFlag", key, value)
        }
    }

    /// If true, _only_ aci safety numbers will be displayed, and e164 safety numbers will not
    /// be displayed.
    public static let onlyAciSafetyNumbers = false

    public static let editMessageSend = true

    /// If true, we will enable recipient hiding, which is like a lighter form of blocking.
    @objc
    public static let recipientHiding = build.includes(.internal)

    @objc
    public static let newTSAccountManager = false

    public static let doNotSendGroupChangeMessagesOnProfileKeyRotation = build.includes(.internal)
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
            featureFlagString = LocalizationNotNeeded("Development")
        case .internalPreview:
            featureFlagString = LocalizationNotNeeded("Internal Preview")
        case .internal:
            featureFlagString = LocalizationNotNeeded("Internal")
        case .openPreview:
            featureFlagString = LocalizationNotNeeded("Open Preview")
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
            LocalizationNotNeeded("Testable build")
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

    @objc
    public static var storageMode: StorageMode {
        if CurrentAppContext().isRunningTests {
            return .grdbTests
        } else {
            return .grdb
        }
    }

    @objc
    public static var storageModeDescription: String {
        return "\(storageMode)"
    }
}

// MARK: -

/// Flags that we'll leave in the code base indefinitely that are helpful for
/// development should go here, rather than cluttering up FeatureFlags.
@objc(SSKDebugFlags)
public class DebugFlags: BaseFlags {
    @objc
    public static let internalLogging = build.includes(.openPreview)

    @objc
    public static let betaLogging = build.includes(.beta)

    @objc
    public static let testPopulationErrorAlerts = build.includes(.beta)

    @objc
    public static let audibleErrorLogging = build.includes(.internal)

    @objc
    public static let internalSettings = build.includes(.internal)

    public static let internalMegaphoneEligible = build.includes(.internal)

    @objc
    public static let reduceLogChatter: Bool = {
        // This is a little verbose to make it easy to change while developing.
        if CurrentAppContext().isRunningTests {
            return true
        }
        return false
    }()

    @objc
    public static let logSQLQueries = build.includes(.dev) && !reduceLogChatter

    @objc
    public static let aggressiveProfileFetching = TestableFlag(false,
                                                               title: LocalizationNotNeeded("Aggressive profile fetching"),
                                                               details: LocalizationNotNeeded("Client will update profiles aggressively."))

    // Currently this flag is only honored by NetworkManager,
    // but we could eventually honor in other places as well:
    //
    // * The socket manager.
    // * Places we make requests using tasks.
    @objc
    public static let logCurlOnSuccess = false

    @objc
    public static let showContextMenuDebugRects = false

    @objc
    public static let verboseNotificationLogging = build.includes(.internal)

    @objc
    public static let deviceTransferVerboseProgressLogging = build.includes(.internal)

    @objc
    public static let reactWithThumbsUpFromLockscreen = build.includes(.internal)

    @objc
    public static let messageDetailsExtraInfo = build.includes(.internal)

    @objc
    public static let exposeCensorshipCircumvention = build.includes(.internal)

    @objc
    public static let allowV1GroupsUpdates = build.includes(.internal)

    @objc
    public static let forceStories = build.includes(.beta)

    @objc
    public static let disableMessageProcessing = TestableFlag(false,
                                                              title: LocalizationNotNeeded("Disable message processing"),
                                                              details: LocalizationNotNeeded("Client will store but not process incoming messages."))

    @objc
    public static let dontSendContactOrGroupSyncMessages = TestableFlag(false,
                                                                        title: LocalizationNotNeeded("Don't send contact or group sync messages"),
                                                                        details: LocalizationNotNeeded("Client will not send contact or group info to linked devices."))

    @objc
    public static let forceAttachmentDownloadFailures = TestableFlag(false,
                                                                     title: LocalizationNotNeeded("Force attachment download failures."),
                                                                     details: LocalizationNotNeeded("All attachment downloads will fail."))

    @objc
    public static let forceAttachmentDownloadPendingMessageRequest = TestableFlag(false,
                                                                                  title: LocalizationNotNeeded("Attachment download vs. message request."),
                                                                                  details: LocalizationNotNeeded("Attachment downloads will be blocked by pending message request."))

    @objc
    public static let forceAttachmentDownloadPendingManualDownload = TestableFlag(false,
                                                                                  title: LocalizationNotNeeded("Attachment download vs. manual download."),
                                                                                  details: LocalizationNotNeeded("Attachment downloads will be blocked by manual download."))

    @objc
    public static let fastPerfTests = false

    @objc
    public static let forceDonorBadgeDisplay = build.includes(.internal)

    @objc
    public static let forceSubscriptionMegaphone = build.includes(.internal)

    @objc
    public static let extraDebugLogs = build.includes(.openPreview)

    @objc
    public static let fakeLinkedDevices = false

    @objc
    public static let paymentsOnlyInContactThreads = true

    @objc
    public static let paymentsIgnoreBlockTimestamps = TestableFlag(false,
                                                                   title: LocalizationNotNeeded("Payments: Ignore ledger block timestamps"),
                                                                   details: LocalizationNotNeeded("Payments will not fill in missing ledger block timestamps"))

    @objc
    public static let paymentsIgnoreCurrencyConversions = TestableFlag(false,
                                                                       title: LocalizationNotNeeded("Payments: Ignore currency conversions"),
                                                                       details: LocalizationNotNeeded("App will behave as though currency conversions are unavailable"))

    @objc
    public static let paymentsHaltProcessing = TestableFlag(false,
                                                            title: LocalizationNotNeeded("Payments: Halt Processing"),
                                                            details: LocalizationNotNeeded("Processing of payments will pause"))

    @objc
    public static let paymentsIgnoreBadData = TestableFlag(false,
                                                           title: LocalizationNotNeeded("Payments: Ignore bad data"),
                                                           details: LocalizationNotNeeded("App will skip asserts for invalid data"))

    @objc
    public static let paymentsFailOutgoingSubmission = TestableFlag(false,
                                                                    title: LocalizationNotNeeded("Payments: Fail outgoing submission"),
                                                                    details: LocalizationNotNeeded("Submission of outgoing transactions will always fail"))

    @objc
    public static let paymentsFailOutgoingVerification = TestableFlag(false,
                                                                      title: LocalizationNotNeeded("Payments: Fail outgoing verification"),
                                                                      details: LocalizationNotNeeded("Verification of outgoing transactions will always fail"))

    @objc
    public static let paymentsFailIncomingVerification = TestableFlag(false,
                                                                      title: LocalizationNotNeeded("Payments: Fail incoming verification"),
                                                                      details: LocalizationNotNeeded("Verification of incoming receipts will always fail"))

    @objc
    public static let paymentsDoubleNotify = TestableFlag(false,
                                                          title: LocalizationNotNeeded("Payments: Double notify"),
                                                          details: LocalizationNotNeeded("App will send two payment notifications and sync messages for each outgoing payment"))

    @objc
    public static let paymentsNoRequestsComplete = TestableFlag(false,
                                                                title: LocalizationNotNeeded("Payments: No requests complete"),
                                                                details: LocalizationNotNeeded("MC SDK network activity never completes"))

    @objc
    public static let paymentsMalformedMessages = TestableFlag(false,
                                                               title: LocalizationNotNeeded("Payments: Malformed messages"),
                                                               details: LocalizationNotNeeded("Payment notifications and sync messages are malformed."))

    @objc
    public static let paymentsSkipSubmissionAndOutgoingVerification = TestableFlag(false,
                                                                                   title: LocalizationNotNeeded("Payments: Skip Submission And Verification"),
                                                                                   details: LocalizationNotNeeded("Outgoing payments won't be submitted or verified."))

    @objc
    public static let messageSendsFail = TestableFlag(false,
                                                      title: LocalizationNotNeeded("Message Sends Fail"),
                                                      details: LocalizationNotNeeded("All outgoing message sends will fail."))

    @objc
    public static let disableUD = TestableFlag(false,
                                               title: LocalizationNotNeeded("Disable sealed sender"),
                                               details: LocalizationNotNeeded("Sealed sender will be disabled for all messages."))

    @objc
    public static let callingUseTestSFU = TestableFlag(false,
                                                       title: LocalizationNotNeeded("Calling: Use Test SFU"),
                                                       details: LocalizationNotNeeded("Group calls will connect to sfu.test.voip.signal.org."))

    @objc
    public static let delayedMessageResend = TestableFlag(false,
                                                          title: LocalizationNotNeeded("Sender Key: Delayed message resend"),
                                                          details: LocalizationNotNeeded("Waits 10s before responding to a resend request."))

    @objc
    public static let showFailedDecryptionPlaceholders = TestableFlag(false,
                                                                      title: LocalizationNotNeeded("Sender Key: Show failed decryption placeholders"),
                                                                      details: LocalizationNotNeeded("Shows placeholder interactions in the conversation list."))

    @objc
    public static let fastPlaceholderExpiration = TestableFlag(
        false,
        title: LocalizationNotNeeded("Sender Key: Early placeholder expiration"),
        details: LocalizationNotNeeded("Shortens the valid window for message resend+recovery."),
        toggleHandler: { _ in
            messageDecrypter.cleanUpExpiredPlaceholders()
        }
    )

    @objc
    public static func logFlags() {
        let logFlag = { (prefix: String, key: String, value: Any?) in
            if let flag = value as? TestableFlag {
                Logger.info("\(prefix): \(key) = \(flag.get())", function: "")
            } else if let value = value {
                Logger.info("\(prefix): \(key) = \(value)", function: "")
            } else {
                Logger.info("\(prefix): \(key) = nil", function: "")
            }
        }

        let flagMap = allFlags()
        for key in Array(flagMap.keys).sorted() {
            let value = flagMap[key]
            logFlag("DebugFlag", key, value)
        }
    }
}

// MARK: -

@objc
public class BaseFlags: NSObject {
    private static func allPropertyNames() -> [String] {
        var propertyCount: CUnsignedInt = 0
        let firstProperty = class_copyPropertyList(object_getClass(self), &propertyCount)
        defer { free(firstProperty) }
        let properties = UnsafeMutableBufferPointer(start: firstProperty, count: Int(propertyCount))
        return properties.map { String(cString: property_getName($0)) }
    }

    public static func allFlags() -> [String: Any] {
        var result = [String: Any]()
        for propertyName in self.allPropertyNames() {
            guard !propertyName.hasPrefix("_") else {
                continue
            }
            guard let value = self.value(forKey: propertyName) else {
                continue
            }
            result[propertyName] = value
        }
        return result
    }

    public static func allTestableFlags() -> [TestableFlag] {
        return self.allFlags().values.compactMap { $0 as? TestableFlag }
    }
}

// MARK: -

@objc
public class TestableFlag: NSObject {
    private let defaultValue: Bool
    private let affectsCapabilities: Bool
    private let flag: AtomicBool
    public let title: String
    public let details: String
    public let toggleHandler: ((Bool) -> Void)?

    fileprivate init(_ defaultValue: Bool,
                     title: String,
                     details: String,
                     affectsCapabilities: Bool = false,
                     toggleHandler: ((Bool) -> Void)? = nil) {
        self.defaultValue = defaultValue
        self.title = title
        self.details = details
        self.affectsCapabilities = affectsCapabilities
        self.flag = AtomicBool(defaultValue)
        self.toggleHandler = toggleHandler

        super.init()

        // Normally we'd store the observer here and remove it in deinit.
        // But TestableFlags are always static; they don't *get* deinitialized except in testing.
        NotificationCenter.default.addObserver(forName: Self.ResetAllTestableFlagsNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.set(self.defaultValue)
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var value: Bool {
        self.get()
    }

    @objc
    public func get() -> Bool {
        guard build.includes(.internal) else {
            return defaultValue
        }
        return flag.get()
    }

    public func set(_ value: Bool) {
        flag.set(value)

        if affectsCapabilities {
            updateCapabilities()
        }
    }

    @objc
    public func switchDidChange(_ sender: UISwitch) {
        set(sender.isOn)
    }

    @objc
    public var switchSelector: Selector {
        #selector(switchDidChange(_:))
    }

    @objc
    public static let ResetAllTestableFlagsNotification = NSNotification.Name("ResetAllTestableFlags")

    private func updateCapabilities() {
        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            TSAccountManager.shared.updateAccountAttributes().asVoid()
        }.done {
            Logger.info("")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }
}
