//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool

    func refreshPreKeysDidSucceed()

    func checkPreKeysIfNecessary(tx: DBReadTransaction)

    func createPreKeys(auth: ChatServiceAuth) -> Promise<Void>

    func createPreKeys(identity: OWSIdentity) -> Promise<Void>

    func rotateSignedPreKeys() -> Promise<Void>

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}
