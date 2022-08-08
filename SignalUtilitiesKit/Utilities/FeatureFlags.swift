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
    public static var useCustomPhotoCapture: Bool {
        return true
    }
}
