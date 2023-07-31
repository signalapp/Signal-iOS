//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Represents an observer who should be notified immediately when username
/// state may have changed.
protocol UsernameChangeDelegate: AnyObject {
    func usernameStateDidChange(newState: Usernames.LocalUsernameState)
}
