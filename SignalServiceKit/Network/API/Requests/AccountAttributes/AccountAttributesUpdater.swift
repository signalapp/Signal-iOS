//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AccountAttributesUpdater {

    /// Sets the flag to force an account attributes update (opening a write tx),
    /// then awaits the current attempt.
    func updateAccountAttributes(authedAccount: AuthedAccount) async throws

    /// Sets the flag to force an account attributes update synchronously,
    /// then initiates an attempt after the transaction ends.
    func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction)
}
