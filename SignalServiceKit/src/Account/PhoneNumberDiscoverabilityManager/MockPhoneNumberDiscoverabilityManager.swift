//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class MockPhoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager {

    public var phoneNumberDiscoverabilityMock: () -> PhoneNumberDiscoverability? = { .everybody }

    open func phoneNumberDiscoverability(tx: DBReadTransaction) -> PhoneNumberDiscoverability? {
        return phoneNumberDiscoverabilityMock()
    }

    public lazy var setPhoneNumberDiscoverabilityMock: (
        _ phoneNumberDiscoverability: PhoneNumberDiscoverability,
        _ updateAccountAttributes: Bool,
        _ updateStorageService: Bool,
        _ authedAccount: AuthedAccount
    ) -> Void = { [weak self] phoneNumberDiscoverability, _, _, _ in
        self?.phoneNumberDiscoverabilityMock = { return phoneNumberDiscoverability }
    }

    open func setPhoneNumberDiscoverability(
        _ phoneNumberDiscoverability: PhoneNumberDiscoverability,
        updateAccountAttributes: Bool,
        updateStorageService: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) {
        setPhoneNumberDiscoverabilityMock(phoneNumberDiscoverability, updateAccountAttributes, updateStorageService, authedAccount)
    }
}

#endif
