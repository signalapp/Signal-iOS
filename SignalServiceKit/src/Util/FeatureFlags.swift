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

let build: FeatureBuild = .production

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
    public static let conversationSearch = true

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
    public static var preserveYdb: Bool {
        return false
    }

    @objc
    public static let uuidCapabilities = !isUsingProductionService

    @objc
    public static var canRevertToYDB: Bool {
        // Only developers should be allowed to use YDB after migrating to GRDB.
        // We don't want to let QA, public beta or production users risk
        // data loss.
        return build == .dev
    }

    @objc
    public static var audibleErrorLogging = build.includes(.internalPreview)

    @objc
    public static var storageModeDescription: String {
        return "\(storageMode)"
    }

    @objc
    public static let stickerReceive = true

    // Don't consult this flag directly; instead consult
    // StickerManager.isStickerSendEnabled.  Sticker sending is
    // auto-enabled once the user receives any sticker content.
    @objc
    public static let stickerSend = true

    @objc
    public static let stickerSharing = true

    @objc
    public static let stickerAutoEnable = true

    @objc
    public static let stickerSearch = false

    @objc
    public static let stickerPackOrdering = false

    // Don't enable this flag until the Desktop changes have been in production for a while.
    @objc
    public static let strictSyncTranscriptTimestamps = false

    @objc
    public static let viewOnceSending = true

    // Don't enable this flag in production.
    @objc
    public static let strictYDBExtensions = build.includes(.beta)

    // Don't enable this flag in production.
    @objc
    public static let onlyModernNotificationClearance = build.includes(.beta)

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
    public static let compareLegacyContactDiscoveryAgainstModern = false

    @objc
    public static let phoneNumberPrivacy = false

    @objc
    public static let cameraFirstCaptureFlow = true

    @objc
    public static let complainAboutSlowDBWrites = true

    @objc
    public static let usernames = allowUUIDOnlyContacts && build.includes(.dev)

    // This can be used to shut down various background operations.
    @objc
    public static let suppressBackgroundActivity = false

    @objc
    public static let verboseAboutView = build.includes(.qa)

    @objc
    public static let logSQLQueries = build.includes(.dev)

    @objc
    public static var calling: Bool {
        // TODO MULTIRING
        return TSAccountManager.sharedInstance().isRegisteredPrimaryDevice
    }

    @objc
    public static let tryToCreateNewGroupsV2 = false

    @objc
    public static let incomingGroupsV2 = false

    @objc
    public static let linkedPhones = build.includes(.internalPreview)

    @objc
    public static let reactionReceive = true

    @objc
    public static let reactionSend = true

    @objc
    public static let isUsingProductionService = true

    @objc
    public static let versionedProfiledFetches = false

    // When we activate this feature flag, we also need to ensure that all
    // users update their profile once in a durable way.
    @objc
    public static let versionedProfiledUpdate = false

    @objc
    public static let useOrphanDataCleaner = true

    @objc
    public static let sendRecipientUpdates = false

    @objc
    public static let useZKGroups = false

    @objc
    public static let pinsForNewUsers = build.includes(.dev)
}
