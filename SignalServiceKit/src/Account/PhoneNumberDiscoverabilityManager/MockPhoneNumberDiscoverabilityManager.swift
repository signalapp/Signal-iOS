//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class MockPhoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager {

    public var hasDefinedIsDiscoverableByPhoneNumberMock: () -> Bool = { false }

    open func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        return hasDefinedIsDiscoverableByPhoneNumberMock()
    }

    public var isDiscoverableByPhoneNumberMock: () -> Bool = { true }

    open func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        return isDiscoverableByPhoneNumberMock()
    }

    public lazy var setIsDiscoverableByPhoneNumberMock: (
        _ isDiscoverable: Bool,
        _ updateStorageService: Bool,
        _ authedAccount: AuthedAccount
    ) -> Void = { [weak self] isDiscoverable, _, _ in
        self?.isDiscoverableByPhoneNumberMock = { return isDiscoverable }
        self?.hasDefinedIsDiscoverableByPhoneNumberMock = { true }
    }

    open func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, updateStorageService: Bool, authedAccount: AuthedAccount, tx: DBWriteTransaction) {
        setIsDiscoverableByPhoneNumberMock(isDiscoverable, updateStorageService, authedAccount)
    }
}

#endif
