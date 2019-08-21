//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .qa

// MARK: -

@objc
public enum StorageMode: Int {
    // Only use YDB.  This should be used in production until we ship
    // the YDB-to-GRDB migration.
    case ydb
    // Use GRDB, migrating if possible on every launch.
    //
    // Supercedes grdbMigratesFreshDBEveryLaunch.
    case grdbThrowaway
    // Use GRDB, migrating once if necessary.
    case grdb
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
        case .ydb:
            return ".ydb"
        case .grdbThrowaway:
            return ".grdbThrowaway"
        case .grdb:
            return ".grdb"
        case .ydbTests:
            return ".ydbTests"
        case .grdbTests:
            return ".grdbTests"
        default:
            owsFailDebug("unexpected StorageMode: \(self)")
            return ".unknown"
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
    public static let conversationSearch = false

    // This flag supercedes useGRDB.
    @objc
    public static var storageMode: StorageMode {
        if CurrentAppContext().isRunningTests {
            // We should be running the tests using both .ydbTests or .grdbTests.
            return .grdbTests
        } else if build.includes(.dev) {
            return .grdbThrowaway
        } else {
            return .ydb
        }
    }

    // This value should eventually be .fail except for production builds
    // where it should be .failDebug.
    @objc
    public static var storageModeStrictness: StorageModeStrictness {
        return .failDebug
    }

    // GRDB TODO: For now, we always load YDB, even if we're launching
    //            after a successful YDB-to-GRDB migration (or for a
    //            new install that never had a YDB database).
    //            Soon, we won't.
    @objc
    public static let alwaysLoadYDB = true

    @objc
    public static var storageModeDescription: String {
        return "\(storageMode)"
    }

    @objc
    public static let shouldPadAllOutgoingAttachments = false

    @objc
    public static let stickerReceive = true

    // Don't consult this flag directly; instead consult
    // StickerManager.isStickerSendEnabled.  Sticker sending is
    // auto-enabled once the user receives any sticker content.
    @objc
    public static let stickerSend = build.includes(.qa)

    @objc
    public static let stickerSharing = build.includes(.qa)

    @objc
    public static let stickerAutoEnable = true

    @objc
    public static let stickerSearch = false

    @objc
    public static let stickerPackOrdering = false

    // Don't enable this flag until the Desktop changes have been in production for a while.
    @objc
    public static let strictSyncTranscriptTimestamps = false

    // This shouldn't be enabled in production until the receive side has been
    // in production for "long enough".
    @objc
    public static let viewOnceSending = build.includes(.qa)

    // Don't enable this flag in production.
    @objc
    public static let strictYDBExtensions = build.includes(.beta)

    // Don't enable this flag in production.
    @objc
    public static let onlyModernNotificationClearance = build.includes(.beta)

    @objc
    public static let registrationLockV2 = !IsUsingProductionService() && build.includes(.dev)

    @objc
    public static var allowUUIDOnlyContacts: Bool {
        // TODO UUID: Remove production check once this rolls out to prod service
        if OWSIsDebugBuild() && !IsUsingProductionService() {
            return true
        } else {
            return false
        }
    }

    @objc
    public static var pinsForEveryone = build.includes(.dev)

    @objc
    public static let useOnlyModernContactDiscovery = !IsUsingProductionService() && build.includes(.dev)

    @objc
    public static let phoneNumberPrivacy = false

    @objc
    public static let socialGraphOnServer = registrationLockV2 && !IsUsingProductionService() && build.includes(.dev)

    @objc
    public static let cameraFirstCaptureFlow = build.includes(.qa)

    @objc
    public static let complainAboutSlowDBWrites = true

    @objc
    public static let usernames = !IsUsingProductionService() && build.includes(.dev)
}
