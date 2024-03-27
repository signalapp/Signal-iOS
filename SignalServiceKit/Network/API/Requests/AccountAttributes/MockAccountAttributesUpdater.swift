//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class MockAccountAttributesUpdater: AccountAttributesUpdater {

    public var updateAccountAttributesMock: (_ authedAccount: AuthedAccount) async throws -> Void = { _ in }

    open func updateAccountAttributes(authedAccount: AuthedAccount) async throws {
        try await updateAccountAttributesMock(authedAccount)
    }

    public var scheduleAccountAttributesUpdateMock: (_ authedAccount: AuthedAccount) -> Void = { _ in }

    open func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction) {
        scheduleAccountAttributesUpdateMock(authedAccount)
    }
}

#endif
