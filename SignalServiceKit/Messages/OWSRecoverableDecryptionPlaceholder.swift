//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension OWSRecoverableDecryptionPlaceholder {

    /// The date after which this placeholder is no longer eligible to be
    /// replaced with recovered original content.
    var expirationDate: Date {
        var expirationInterval = RemoteConfig.current.replaceableInteractionExpiration
        owsAssertDebug(expirationInterval >= 0)

        if DebugFlags.fastPlaceholderExpiration.get() {
            expirationInterval = min(expirationInterval, 5.0)
        }

        return self.receivedAtDate.addingTimeInterval(max(0, expirationInterval))
    }
}
