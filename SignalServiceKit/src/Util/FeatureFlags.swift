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

    /// iOS has long supported sending oversized text as a sidecar attachment. The other clients
    /// simply displayed it as a text attachment. As part of the new cross-client long-text feature,
    /// we want to be able to display long text with attachments as well. Existing iOS clients
    /// won't properly display this, so we'll need to wait a while for rollout.
    /// The stakes aren't __too__ high, because legacy clients won't lose data - they just won't
    /// see the media attached to a long text message until they update their client.
    @objc
    public static var sendingMediaWithOversizeText: Bool {
        return false
    }

    @objc
    public static var useCustomPhotoCapture: Bool {
        return true
    }

    @objc
    public static var useGRDB: Bool {
        if OWSIsDebugBuild() {
            return true
        } else {
            return false
        }
    }

    // Temporary flag helpful for development, where blowing away GRDB and re-running
    // the migration every launch is helpful.
    public
    static let grdbMigratesFreshDBEveryLaunch = false
}
