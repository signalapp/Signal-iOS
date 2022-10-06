//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

extension AppVersion {
    /// Get the database corruption state as a string.
    ///
    /// We can remove this if we move its callers to Swift; it is only here to ease interopability.
    @objc
    public var databaseCorruptionStateString: String {
        let userDefaults = CurrentAppContext().appUserDefaults()
        let state = DatabaseCorruptionState(userDefaults: userDefaults)
        return String(describing: state)
    }
}
