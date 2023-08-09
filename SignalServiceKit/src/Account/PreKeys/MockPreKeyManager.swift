//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

internal class MockPreKeyManager: PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: SignalServiceKit.DBReadTransaction) -> Bool { false }
    func refreshPreKeysDidSucceed() { }
    func checkPreKeysIfNecessary(tx: SignalServiceKit.DBReadTransaction) { }
    func legacy_createPreKeys(auth: SignalServiceKit.ChatServiceAuth) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func rotateSignedPreKeys() -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) { }
}
