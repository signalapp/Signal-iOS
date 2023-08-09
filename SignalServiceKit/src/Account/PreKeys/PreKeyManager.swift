//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool

    func checkPreKeysIfNecessary(tx: DBReadTransaction)

    func legacy_createPreKeys(auth: ChatServiceAuth) -> Promise<Void>

    /// Our local PNI can get out of sync with the server, including because we never had
    /// a PNI or the server never got ours. In these cases we create new PNI prekeys
    /// to give to the server, ignoring any old ones we may have had.
    func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> Promise<Void>

    func rotateSignedPreKeys() -> Promise<Void>

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}
