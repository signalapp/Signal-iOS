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

let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .beta

/// By centralizing feature flags here and documenting their rollout plan, it's easier to review
/// which feature flags are in play.
@objc(SSKFeatureFlags)
public class FeatureFlags: NSObject {

    @objc
    public static let conversationSearch = false

    @objc
    public static var useGRDB = false

    @objc
    public static let shouldPadAllOutgoingAttachments = false

    // Temporary flag helpful for development, where blowing away GRDB and re-running
    // the migration every launch is helpful.
    @objc
    public static let grdbMigratesFreshDBEveryLaunch = true

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
    public static let messageRequest = build.includes(.qa)
}
