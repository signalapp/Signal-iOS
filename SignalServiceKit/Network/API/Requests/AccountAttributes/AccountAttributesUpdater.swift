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

/// Just a container for simple static helper methods on AccountAttributesUpdater
/// that can be shared with other classes (incl. objc classes).
@objc
public final class AccountAttributesUpdaterObjcBridge: NSObject {

    private override init() {}

    // Sets the flag to force an account attributes update,
    // then returns a promise for the current attempt.
    @objc
    @available(swift, obsoleted: 1.0)
    @discardableResult
    public static func updateAccountAttributes() -> AnyPromise {
        let promise = Promise.wrapAsync {
            try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
        }
        return AnyPromise(promise)
    }
}
