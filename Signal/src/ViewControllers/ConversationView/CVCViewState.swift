//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// TODO: We need to decompose CVC. This can be a simple place to hang
//       mutable view state. I'd like to slowly migrate more CVC state here.
// TODO: Pull this out into its own source file.
@objc
public class CVCViewState: NSObject {
    // These properties should only be accessed on the main thread.
    @objc
    public var isPendingMemberRequestsBannerHidden = false
    @objc
    public var isMigrateGroupBannerHidden = false
    @objc
    public var isDroppedGroupMembersBannerHidden = false
    @objc
    public var hasTriedToMigrateGroup = false
}
