//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

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
    public static let uuidCapabilities = (allowUUIDOnlyContacts && useOnlyModernContactDiscovery) || groupsV2

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
    public static let allowUUIDOnlyContacts = useOnlyModernContactDiscovery || groupsV2

    @objc
    public static let uuidSafetyNumbers = allowUUIDOnlyContacts

    @objc
    public static let useOnlyModernContactDiscovery = false

    @objc
    public static let compareLegacyContactDiscoveryAgainstModern = !isUsingProductionService

    @objc
    public static let phoneNumberPrivacy = false

    @objc
    public static let socialGraphOnServer = false

    @objc
    public static let complainAboutSlowDBWrites = true

    @objc
    public static let usernames = allowUUIDOnlyContacts && build.includes(.dev)

    @objc
    public static let messageRequest = build.includes(.dev) && socialGraphOnServer

    @objc
    public static let profileDisplayChanges = build.includes(.dev)

    @objc
    public static var calling: Bool {
        return answerCallsOnSecondaryDevice || TSAccountManager.sharedInstance().isRegisteredPrimaryDevice
    }

    // We can't enable this in production until sending calls to all devices has
    // rolled out on iOS and Android.
    //
    // Note: As well as exposing incoming calls on iPads, this also exposes the outgoing call button
    // on iPads, because we don't want to allow outgoing calls from an iPad until we're also ready
    // to receive them on iPad.
    @objc
    public static let answerCallsOnSecondaryDevice: Bool = true

    @objc
    public static let groupsV2 = build.includes(.qa)

    // Don't consult this feature flag directly; instead
    // consult RemoteConfig.groupsV2CreateGroups.
    @objc
    public static let groupsV2CreateGroups = groupsV2

    // Don't consult this feature flag directly; instead
    // consult RemoteConfig.groupsV2GoodCitizen.
    @objc
    public static let groupsV2GoodCitizen = groupsV2

    // The other clients don't consider this MVP, but we already implemented it.
    // It enables an optimization where other clients can usually update without
    // interacting with the service.
    //
    // GroupsV2 TODO: Decide whether or not to set this flag.
    @objc
    public static let groupsV2embedProtosInGroupUpdates = false

    @objc
    public static let groupsV2processProtosInGroupUpdates = false

    // Don't consult this feature flag directly; instead
    // consult RemoteConfig.groupsV2SetCapability.
    @objc
    public static let groupsV2SetCapability = groupsV2

    @objc
    public static let groupsV2reapplyCurrentRevision = false

    @objc
    public static let linkedPhones = build.includes(.internalPreview)

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
    private static let _groupsV2dontSendUpdates = AtomicBool(false)
    @objc
    public static var groupsV2dontSendUpdates: Bool {
        get {
            guard build.includes(.qa) else {
                return false
            }
            return _groupsV2dontSendUpdates.get()
        }
        set {
            _groupsV2dontSendUpdates.set(newValue)
        }
    }

    @objc
    public static let groupsV2showV2Indicator = FeatureFlags.groupsV2 && build.includes(.qa)

    // If set, v2 groups will be created and updated with invalid avatars
    // so that we can test clients' robustness to this case.
    @objc
    public static let groupsV2corruptAvatarUrlPaths = false

    // If set, v2 groups will be created and updated with
    // corrupt avatars, group names, and/or dm state
    // so that we can test clients' robustness to this case.
    @objc
    public static let groupsV2corruptBlobEncryption = false

    // This flag auto-enables the groupv2 flags in RemoteConfig.
    @objc
    public static let groupsV2IgnoreServerFlags = FeatureFlags.groupsV2 && build.includes(.qa)

    // If set, client will invite instead of adding other users.
    private static let _groupsV2forceInvites = AtomicBool(false)
    @objc
    public static var groupsV2forceInvites: Bool {
        get {
            guard build.includes(.qa) else {
                return false
            }
            return _groupsV2forceInvites.get()
        }
        set {
            _groupsV2forceInvites.set(newValue)
        }
    }

    @objc
    public static let groupsV2memberStatusIndicators = FeatureFlags.groupsV2 && build.includes(.qa)

    @objc
    public static let groupsV2editMemberAccess = build.includes(.qa)

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
    public static let verboseNotificationLogging = build.includes(.qa)

    @objc
    public static let verboseSignalRecipientLogging = build.includes(.qa)

    @objc
    public static let shouldMergeUserProfiles = build.includes(.qa)

    @objc
    public static let deviceTransferVerboseProgressLogging = build.includes(.qa)

    // We currently want to force-enable versioned profiles for
    // all beta users, but not production.
    @objc
    public static let forceVersionedProfiles = build.includes(.beta)

    public static func buildFlagMap() -> [String: Any] {
        BaseFlags.buildFlagMap(for: DebugFlags.self) { (key: String) -> Any? in
            DebugFlags.value(forKey: key)
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
