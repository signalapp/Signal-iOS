//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSDisappearingMessagesJob {
    /// Is the database corrupted? If so, we don't want to start the job.
    ///
    /// This is most likely to happen outside the main app, like in an extension, where we might not
    /// check for corruption before marking the app ready.
    @objc
    class func isDatabaseCorrupted() -> Bool {
        return DatabaseCorruptionState(userDefaults: CurrentAppContext().appUserDefaults())
            .status
            .isCorrupted
    }
}
