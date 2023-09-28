//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PhoneNumberDiscoverabilityManager {

    func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool

    func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool

    func setIsDiscoverableByPhoneNumber(
        _ isDiscoverable: Bool,
        updateStorageService: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    )
}
