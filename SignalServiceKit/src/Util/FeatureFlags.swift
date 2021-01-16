//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

enum FeatureBuild: Int {
    case dev
    case internalPreview
    case qa
    case beta
    case production
}

extension FeatureBuild {
    func includes(_ level: FeatureBuild) -> Bool {
        return self.rawValue <= level.rawValue
    }
}

let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .production

// MARK: -

@objc
public enum StorageMode: Int {
    // Only use YDB.  This should be used in production until we ship
    // the YDB-to-GRDB migration.
    case ydbForAll
    // Use GRDB, migrating if possible on every launch.
    // If no YDB database exists, a throwaway db is not used.
    //
    // Supercedes grdbMigratesFreshDBEveryLaunch.
    //
    // TODO: Remove.
    case grdbThrowawayIfMigrating
    // Use GRDB under certain conditions.
    //
    // TODO: Remove.
    case grdbForAlreadyMigrated
    case grdbForLegacyUsersOnly
    case grdbForNewUsersOnly
    // Use GRDB, migrating once if necessary.
    case grdbForAll
    // These modes can be used while running tests.
    // They are more permissive than the release modes.
    //
    // The build shepherd should be running the test
    // suites in .ydbTests and .grdbTests modes before each release.
    case ydbTests
    case grdbTests
}

// MARK: -

extension StorageMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ydbForAll:
            return ".ydbForAll"
        case .grdbThrowawayIfMigrating:
            return ".grdbThrowawayIfMigrating"
        case .grdbForAlreadyMigrated:
            return ".grdbForAlreadyMigrated"
        case .grdbForLegacyUsersOnly:
            return ".grdbForLegacyUsersOnly"
        case .grdbForNewUsersOnly:
            return ".grdbForNewUsersOnly"
        case .grdbForAll:
            return ".grdbForAll"
        case .ydbTests:
            return ".ydbTests"
        case .grdbTests:
            return ".grdbTests"
        }
    }
}

// MARK: -

@objc
public enum StorageModeStrictness: Int {
    // For DEBUG, QA and beta builds only.
    case fail
    // For production
    case failDebug
    // Temporary value to be used until existing issues are resolved.
    case log
}

// MARK: -

/// By centralizing feature flags here and documenting their rollout plan, it's easier to review
/// which feature flags are in play.
@objc(SSKFeatureFlags)
public class FeatureFlags: BaseFlags {

    @objc
    public static var storageMode: StorageMode {
        if CurrentAppContext().isRunningTests {
            // We should be running the tests using both .ydbTests or .grdbTests.
            return .grdbTests
        } else {
            return .grdbForAll
        }
    }

    // Don't enable this flag in production.
    // At least, not yet.
    @objc
    public static var storageModeStrictness: StorageModeStrictness {
        return build.includes(.beta) ? .fail : .failDebug
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

    // Don't enable this flag in production.
    @objc
    public static let strictYDBExtensions = build.includes(.beta)

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
    public static var groupsV2Migrations = true

    @objc
    public static let groupsV2MigrationSetCapability = groupsV2Migrations

    @objc
    public static let linkedPhones = build.includes(.qa)

    @objc
    public static let isUsingProductionService = true

    @objc
    public static let useOrphanDataCleaner = true

    @objc
    public static let sendRecipientUpdates = false

    @objc
    public static let notificationServiceExtension = build.includes(.dev)

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

    public static func buildFlagMap() -> [String: Any] {
        BaseFlags.buildFlagMap(for: FeatureFlags.self) { (key: String) -> Any? in
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
    public static let internalLogging = build.includes(.qa)

    // DEBUG builds won't receive push notifications, which prevents receiving messages
    // while the app is backgrounded or the system call screen is active.
    //
    // Set this flag to true to be able to download messages even when the app is in the background.
    @objc
    public static let keepWebSocketOpenInBackground = false

    @objc
    public static let audibleErrorLogging = build.includes(.qa)

    @objc
    public static let verboseAboutView = build.includes(.qa)

    // This can be used to shut down various background operations.
    @objc
    public static let suppressBackgroundActivity = false

    @objc
    public static let logSQLQueries = build.includes(.dev)

    @objc
    public static let groupsV2IgnoreCapability = false

    // We can use this to test recovery from "missed updates".
    @objc
    public static let groupsV2dontSendUpdates = TestableFlag(false)

    @objc
    public static let groupsV2showV2Indicator = FeatureFlags.groupsV2Supported && build.includes(.qa)

    // If set, v2 groups will be created and updated with invalid avatars
    // so that we can test clients' robustness to this case.
    @objc
    public static let groupsV2corruptAvatarUrlPaths = TestableFlag(false)

    // If set, v2 groups will be created and updated with
    // corrupt avatars, group names, and/or dm state
    // so that we can test clients' robustness to this case.
    @objc
    public static let groupsV2corruptBlobEncryption = TestableFlag(false)

    // If set, client will invite instead of adding other users.
    @objc
    public static let groupsV2forceInvites = TestableFlag(false)

    // If set, client will always send corrupt invites.
    @objc
    public static let groupsV2corruptInvites = TestableFlag(false)

    @objc
    public static let groupsV2onlyCreateV1Groups = TestableFlag(false)

    @objc
    public static let groupsV2migrationsForceEnableAutoMigrations = TestableFlag(build.includes(.beta))

    @objc
    public static let groupsV2migrationsForceEnableManualMigrations = TestableFlag(build.includes(.qa))

    @objc
    public static let groupsV2MigrationForceBlockingMigrations = TestableFlag(false)

    @objc
    public static let groupsV2migrationsDropOtherMembers = TestableFlag(false)

    @objc
    public static let groupsV2migrationsInviteOtherMembers = TestableFlag(false)

    @objc
    public static let groupsV2migrationsDisableMigrationCapability = TestableFlag(false, affectsCapabilities: true)

    @objc
    public static let groupsV2migrationsIgnoreMigrationCapability = false

    @objc
    public static let aggressiveProfileFetching = TestableFlag(false)

    @objc
    public static let groupsV2ignoreCorruptInvites = false

    @objc
    public static let groupsV2memberStatusIndicators = FeatureFlags.groupsV2Supported && build.includes(.qa)

    @objc
    public static let isMessageProcessingVerbose = false

    // Currently this flag is only honored by TSNetworkManager,
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
    public static let showProfileKeyAndUuidsIndicator = build.includes(.qa)

    @objc
    public static let showCapabilityIndicators = build.includes(.qa)

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
    public static let disableMessageProcessing = TestableFlag(false)

    @objc
    public static let dontSendContactOrGroupSyncMessages = TestableFlag(false)

    @objc
    public static let forceAttachmentDownloadFailures = TestableFlag(false)

    @objc
    public static let forceAttachmentDownloadPendingMessageRequest = TestableFlag(false)

    @objc
    public static let forceAttachmentDownloadPendingManualDownload = TestableFlag(false)

    @objc
    public static let fastPerfTests = false

    @objc
    public static let messageSendsFail = false

    @objc
    public static let extraDebugLogs = build.includes(.qa)

    @objc
    public static let shouldShowColorPicker = false

    public static func buildFlagMap() -> [String: Any] {
        BaseFlags.buildFlagMap(for: DebugFlags.self) { (key: String) -> Any? in
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
}

// MARK: -

@objc
public class TestableFlag: NSObject {
    private let defaultValue: Bool
    private let affectsCapabilities: Bool
    private let flag: AtomicBool

    fileprivate init(_ defaultValue: Bool, affectsCapabilities: Bool = false) {
        self.defaultValue = defaultValue
        self.affectsCapabilities = affectsCapabilities
        self.flag = AtomicBool(defaultValue)

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
            TSAccountManager.shared().updateAccountAttributes().asVoid()
        }.done {
            Logger.info("")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }
}
