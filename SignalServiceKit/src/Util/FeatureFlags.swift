//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

private enum FeatureBuild: Int {
    case dev
    case internalPreview
    case qa
    case openPreview
    case beta
    case production
}

extension FeatureBuild {
    func includes(_ level: FeatureBuild) -> Bool {
        return self.rawValue <= level.rawValue
    }
}

private let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .production

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
        case .qa:
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
            #elseif RELEASE
            // RELEASE can be inferred from the lack of configuration. This will only be hit if the outer #if is removed.
            nil
            #else
            owsFailDebug("Invalid configuration")
            return "*"
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

    @objc
    public static let stickerSearch = false

    @objc
    public static let stickerPackOrdering = false

    // Don't enable this flag until the Desktop changes have been in production for a while.
    @objc
    public static let strictSyncTranscriptTimestamps = false

    @objc
    public static let phoneNumberSharing = build.includes(.qa)

    @objc
    public static let phoneNumberDiscoverability = build.includes(.qa)

    @objc
    public static let complainAboutSlowDBWrites = true

    // Don't consult this flags; consult RemoteConfig.usernames.
    static let usernamesSupported = build.includes(.qa)

    // Don't consult this flags; consult RemoteConfig.groupsV2...
    static var groupsV2Supported: Bool { !CurrentAppContext().isRunningTests }

    @objc
    public static let groupsV2embedProtosInGroupUpdates = true

    @objc
    public static let groupsV2processProtosInGroupUpdates = true

    @objc
    public static let groupsV2showSplash = build.includes(.beta)

    @objc
    public static let linkedPhones = build.includes(.qa)

    @objc
    public static var isUsingProductionService: Bool {
        if paymentsInternalBeta {
            return false
        } else {
            return true
        }
    }

    @objc
    public static let sendRecipientUpdates = false

    @objc
    public static let pinsForNewUsers = true

    @objc
    public static let deviceTransferDestroyOldDevice = true

    @objc
    public static let deviceTransferThrowAway = false

    @objc
    public static let attachmentUploadV3ForV1GroupAvatars = false

    @objc
    public static let supportAnimatedStickers_Lottie = false

    @objc
    public static let supportAnimatedStickers_Apng = true

    @objc
    public static let supportAnimatedStickers_AnimatedWebp = true

    @objc
    public static let paymentsInternalBeta = false

    @objc
    public static let paymentsBeta = true

    @objc
    public static let paymentsEnabled = paymentsBeta

    @objc
    public static let paymentsRequests = false

    @objc
    public static let paymentsScrubDetails = false

    @objc
    public static let spamChallenges = false

    @objc
    public static let universalDisappearingMessages = true

    @objc
    public static let groupDescriptionEditing = true

    @objc
    public static let contextMenus = true

    @objc
    public static let communicationStyleNotifications = true

    @objc
    public static let newLinkDeviceScheme = build.includes(.dev)

    @objc
    public static let forceEnableGiphyMP4 = build.includes(.beta)

    @objc
    public static let deprecateREST = false

    @objc
    public static let newHostNames = true

    @objc
    public static let groupRings = false

    @objc
    public static let canUseNativeWebsocket = false

    @objc
    public static var notificationServiceExtension: Bool {
        // The CallKit APIs for the NSE are only available from iOS 14.5 and on,
        // however there is a significant bug in iOS 14 where the NSE will not
        // launch properly after a crash so we only support it in iOS 15.
        if #available(iOS 15, *) { return true }
        return false
    }

    public static func buildFlagMap() -> [String: Any] {
        BaseFlags.buildFlagMap(for: FeatureFlags.self) { (key: String) -> Any? in
            FeatureFlags.value(forKey: key)
        }
    }

    public static var allTestableFlags: [TestableFlag] {
        BaseFlags.findTestableFlags(for: FeatureFlags.self) { (key: String) -> Any? in
            FeatureFlags.value(forKey: key)
        }
    }

    @objc
    public static func logFlags() {
        let logFlag = { (prefix: String, key: String, value: Any?) in
            if let value = value {
                Logger.info("\(prefix): \(key) = \(value)", function: "")
            } else {
                Logger.info("\(prefix): \(key) = nil", function: "")
            }
        }

        let flagMap = buildFlagMap()
        for key in Array(flagMap.keys).sorted() {
            let value = flagMap[key]
            logFlag("FeatureFlag", key, value)
        }
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

    // DEBUG builds won't receive push notifications, which prevents receiving messages
    // while the app is backgrounded or the system call screen is active.
    //
    // Set this flag to true to be able to download messages even when the app is in the background.
    @objc
    public static let keepWebSocketOpenInBackground = false

    @objc
    public static let testPopulationErrorAlerts = build.includes(.beta)

    @objc
    public static let audibleErrorLogging = build.includes(.qa)

    @objc
    public static let internalSettings = build.includes(.qa)

    // This can be used to shut down various background operations.
    @objc
    public static let suppressBackgroundActivity = false

    @objc
    public static let reduceLogChatter: Bool = {
        if CurrentAppContext().isRunningTests {
            return true
        }
        return false && build.includes(.dev)
    }()

    @objc
    public static let logSQLQueries = build.includes(.dev) && !reduceLogChatter

    @objc
    public static let groupsV2IgnoreCapability = false

    // We can use this to test recovery from "missed updates".
    @objc
    public static let groupsV2dontSendUpdates = TestableFlag(false,
                                                             title: LocalizationNotNeeded("Groups v2: Don't Send Updates"),
                                                             details: LocalizationNotNeeded("The app will not send 'group update' messages for v2 groups. " +
                                                                                                "Other group members will only learn of group changes from normal group messages."))

    // If set, v2 groups will be created and updated with invalid avatars
    // so that we can test clients' robustness to this case.
    @objc
    public static let groupsV2corruptAvatarUrlPaths = TestableFlag(false,
                                                                   title: LocalizationNotNeeded("Groups v2: Corrupt avatar URL paths"),
                                                                   details: LocalizationNotNeeded("Client will update group state with corrupt avatar URL paths."))

    // If set, v2 groups will be created and updated with
    // corrupt avatars, group names, and/or dm state
    // so that we can test clients' robustness to this case.
    @objc
    public static let groupsV2corruptBlobEncryption = TestableFlag(false,
                                                                   title: LocalizationNotNeeded("Groups v2: Corrupt blobs"),
                                                                   details: LocalizationNotNeeded("Client will update group state with corrupt blobs."))

    // If set, client will invite instead of adding other users.
    @objc
    public static let groupsV2forceInvites = TestableFlag(false,
                                                          title: LocalizationNotNeeded("Groups v2: Always Invite"),
                                                          details: LocalizationNotNeeded("Members added to a v2 group will always be invited instead of added."))

    // If set, client will always send corrupt invites.
    @objc
    public static let groupsV2corruptInvites = TestableFlag(false,
                                                            title: LocalizationNotNeeded("Groups v2: Corrupt Invites"),
                                                            details: LocalizationNotNeeded("Client will only emit corrupt invites to v2 groups."))

    @objc
    public static let groupsV2onlyCreateV1Groups = TestableFlag(false,
                                                                title: LocalizationNotNeeded("Groups v2: Only create v1 groups"),
                                                                details: LocalizationNotNeeded("Client will not try to create v2 groups."))

    @objc
    public static let groupsV2migrationsDropOtherMembers = TestableFlag(false,
                                                                        title: LocalizationNotNeeded("Groups v2: Migrations drop others"),
                                                                        details: LocalizationNotNeeded("Group migrations will drop other members."))

    @objc
    public static let groupsV2migrationsInviteOtherMembers = TestableFlag(false,
                                                                          title: LocalizationNotNeeded("Groups v2: Migrations invite others"),
                                                                          details: LocalizationNotNeeded("Group migrations will invite other members."))

    @objc
    public static let groupsV2migrationsIgnoreMigrationCapability = false

    @objc
    public static let aggressiveProfileFetching = TestableFlag(false,
                                                               title: LocalizationNotNeeded("Aggressive profile fetching"),
                                                               details: LocalizationNotNeeded("Client will update profiles aggressively."))

    @objc
    public static let groupsV2ignoreCorruptInvites = false

    @objc
    public static let groupsV2memberStatusIndicators = FeatureFlags.groupsV2Supported && build.includes(.qa)

    @objc
    public static let isMessageProcessingVerbose = false

    // Currently this flag is only honored by NetworkManager,
    // but we could eventually honor in other places as well:
    //
    // * The socket manager.
    // * Places we make requests using tasks.
    @objc
    public static let logCurlOnSuccess = false

    // Our "group update" info messages should be robust to
    // various situations that shouldn't occur in production,
    // bug we want to be able to test them using the debug UI.
    @objc
    public static let permissiveGroupUpdateInfoMessages = build.includes(.dev)

    @objc
    public static let showContextMenuDebugRects = false

    @objc
    public static let verboseNotificationLogging = build.includes(.qa)

    @objc
    public static let verboseSignalRecipientLogging = build.includes(.qa)

    @objc
    public static let shouldMergeUserProfiles = build.includes(.qa)

    @objc
    public static let deviceTransferVerboseProgressLogging = build.includes(.qa)

    @objc
    public static let reactWithThumbsUpFromLockscreen = build.includes(.qa)

    @objc
    public static let messageDetailsExtraInfo = build.includes(.qa)

    @objc
    public static let exposeCensorshipCircumvention = build.includes(.qa)

    @objc
    public static let allowV1GroupsUpdates = build.includes(.qa)

    @objc
    public static let forceProfilesForAll = build.includes(.beta)

    @objc
    public static let forceGroupCalling = build.includes(.beta)

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
    public static let forceViewedReceiptSending = true

    @objc
    public static let forceDonorBadgeDisplay = build.includes(.qa)

    @objc
    public static let forceDonorBadgeAcquisition = build.includes(.qa)

    @objc
    public static let forceSubscriptionMegaphone = build.includes(.qa)

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
    public static let paymentsAllowAllCountries = FeatureFlags.paymentsInternalBeta

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
    public static let fastPlaceholderExpiration = TestableFlag(false,
                                                               title: LocalizationNotNeeded("Sender Key: Early placeholder expiration"),
                                                               details: LocalizationNotNeeded("Shortens the valid window for message resend+recovery."),
                                                               toggleHandler: { _ in
                                                                databaseStorage.read { messageDecrypter.schedulePlaceholderCleanup(transaction: $0)}
                                                               })

    public static func buildFlagMap() -> [String: Any] {
        BaseFlags.buildFlagMap(for: DebugFlags.self) { (key: String) -> Any? in
            DebugFlags.value(forKey: key)
        }
    }

    public static var allTestableFlags: [TestableFlag] {
        BaseFlags.findTestableFlags(for: DebugFlags.self) { (key: String) -> Any? in
            DebugFlags.value(forKey: key)
        }
    }

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

        let flagMap = buildFlagMap()
        for key in Array(flagMap.keys).sorted() {
            let value = flagMap[key]
            logFlag("DebugFlag", key, value)
        }
    }
}

// MARK: -

@objc
public class BaseFlags: NSObject {
    static func buildFlagMap(for flagsClass: Any, flagFunc: (String) -> Any?) -> [String: Any] {
        var result = [String: Any]()
        var count: CUnsignedInt = 0
        let methods = class_copyPropertyList(object_getClass(flagsClass), &count)!
        for i in 0 ..< count {
            let selector = property_getName(methods.advanced(by: Int(i)).pointee)
            if let key = String(cString: selector, encoding: .utf8) {
                guard !key.hasPrefix("_") else {
                    continue
                }
                if let value = flagFunc(key) {
                    result[key] = value
                }
            }
        }
        return result
    }

    static func findTestableFlags(for flagsClass: Any, flagFunc: (String) -> Any?) -> [TestableFlag] {
        var result = [TestableFlag]()
        var count: CUnsignedInt = 0
        let methods = class_copyPropertyList(object_getClass(flagsClass), &count)!
        for i in 0 ..< count {
            let selector = property_getName(methods.advanced(by: Int(i)).pointee)
            if let key = String(cString: selector, encoding: .utf8) {
                guard !key.hasPrefix("_") else {
                    continue
                }
                if let value = flagFunc(key) as? TestableFlag {
                    result.append(value)
                }
            }
        }
        return result
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
        guard build.includes(.qa) else {
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
        firstly(on: .global()) { () -> Promise<Void> in
            TSAccountManager.shared.updateAccountAttributes().asVoid()
        }.done {
            Logger.info("")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }
}
