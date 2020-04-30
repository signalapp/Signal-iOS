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

let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .beta

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
public class FeatureFlags: NSObject {

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
    public static let uuidCapabilities = !isUsingProductionService

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
    public static var allowUUIDOnlyContacts: Bool {
        // TODO UUID: Remove production check once this rolls out to prod service
        if OWSIsDebugBuild() && !isUsingProductionService {
            return true
        } else {
            return false
        }
    }

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
        return multiRing || TSAccountManager.sharedInstance().isRegisteredPrimaryDevice
    }

    // TODO MULTIRING
    @objc
    public static let multiRing: Bool = false

    @objc
    public static let groupsV2 = build.includes(.qa) && !isUsingProductionService

    // Don't consult this feature flag directly; instead
    // consult RemoteConfig.groupsV2CreateGroups.
    @objc
    public static let groupsV2CreateGroups = groupsV2

    // Don't consult this feature flag directly; instead
    // consult RemoteConfig.groupsV2IncomingMessages.
    @objc
    public static let groupsV2IncomingMessages = groupsV2

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
    public static let linkedPhones = build.includes(.internalPreview)

    @objc
    public static let isUsingProductionService = true

    @objc
    public static let versionedProfiledFetches = groupsV2

    // When we activate this feature flag, we also need to ensure that all
    // users update their profile once in a durable way.
    @objc
    public static let versionedProfiledUpdate = groupsV2

    @objc
    public static let useOrphanDataCleaner = true

    @objc
    public static let sendRecipientUpdates = false

    @objc
    public static let notificationServiceExtension = build.includes(.dev)

    @objc
    public static let pinsForNewUsers = true
}

/// Flags that we'll leave in the code base indefinitely that are helpful for
/// development should go here, rather than cluttering up FeatureFlags.
@objc(SSKDebugFlags)
public class DebugFlags: NSObject {
    // DEBUG builds won't receive push notifications, which prevents receiving messages
    // while the app is backgrounded or the system call screen is active.
    //
    // Set this flag to true to be able to download messages even when the app is in the background.
    @objc
    public static let keepWebSocketOpenInBackground = false

    @objc
    public static var audibleErrorLogging = build.includes(.internalPreview)

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
    public static let groupsV2dontSendUpdates = false

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
    public static let groupsV2IgnoreServerFlags = FeatureFlags.groupsV2

    // If set, this will invite instead of adding other users.
    @objc
    public static let groupsV2forceInvites = false

    @objc
    public static var groupsV2memberStatusIndicators = FeatureFlags.groupsV2 && build.includes(.qa)

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
    public static let showProfileKeyIndicator = build.includes(.qa)
}
