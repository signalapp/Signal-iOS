//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// By centralizing feature flags here and documenting their rollout plan, it's easier to review
/// which feature flags are in play.
@objc(SSKFeatureFlags)
public class FeatureFlags: NSObject {

    @objc
    public static var conversationSearch: Bool {
        return false
    }

    @objc
    public static var useGRDB: Bool {
        if OWSIsDebugBuild() {
            return true
        } else {
            return false
        }
    }

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
    public static let stickerSend = true

    @objc
    public static let stickerSharing = false

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
    public static let ephemeralMessageSend = true

    // This shouldn't be enabled in production until the receive side has been
    // in production for "long enough".
    @objc
    public static let perMessageExpiration = true
}
