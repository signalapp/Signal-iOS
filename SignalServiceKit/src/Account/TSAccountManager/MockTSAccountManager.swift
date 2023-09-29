//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

public class MockTSAccountManager: TSAccountManagerProtocol {

    public var dateProvider: DateProvider

    public init(dateProvider: @escaping DateProvider = { Date() }) {
        self.dateProvider = dateProvider
    }

    public var warmCachesMock: (() -> Void)?

    open func warmCaches() {
        warmCachesMock?()
    }

    public var localIdentifiersMock: (() -> LocalIdentifiers?) = {
        return LocalIdentifiers(
            aci: .randomForTesting(),
            pni: .randomForTesting(),
            e164: .init("+15555555555")!
        )
    }

    open var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { localIdentifiersMock() }

    open func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return localIdentifiersWithMaybeSneakyTransaction
    }

    // MARK: - RegistrationIds

    public var aciRegistrationIdMock: () -> UInt32 = {
        let id = RegistrationIdGenerator.generate()
        return { id }
    }()

    open func getOrGenerateAciRegistrationId(tx: DBWriteTransaction) -> UInt32 {
        aciRegistrationIdMock()
    }

    public var pniRegistrationIdMock: () -> UInt32 = {
        let id = RegistrationIdGenerator.generate()
        return { id }
    }()

    open func getOrGeneratePniRegistrationId(tx: DBWriteTransaction) -> UInt32 {
        return pniRegistrationIdMock()
    }

    // MARK: - Manual Message Fetch

    public var isManualMessageFetchEnabledMock: () -> Bool = { false }

    open func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool {
        return isManualMessageFetchEnabledMock()
    }

    public lazy var setIsManualMessageFetchEnabledMock: (
        Bool
    ) -> Void = { [weak self] isManualMessageFetchEnabled in
        self?.isManualMessageFetchEnabledMock = { isManualMessageFetchEnabled }
    }

    open func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
        setIsManualMessageFetchEnabledMock(isEnabled)
    }

    // MARK: - Phone Number Discoverability

    public var hasDefinedIsDiscoverableByPhoneNumberMock: () -> Bool = { false }

    open func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        return hasDefinedIsDiscoverableByPhoneNumberMock()
    }

    public var isDiscoverableByPhoneNumberMock: () -> Bool = { true }

    open func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        return isDiscoverableByPhoneNumberMock()
    }

    public lazy var lastSetIsDiscoverablyByPhoneNumberAtMock: () -> Date = dateProvider

    public lazy var setIsDiscoverableByPhoneNumberMock: (
        Bool
    ) -> Void = { [weak self] isDiscoverableByPhoneNumber in
        guard let self else { return }
        self.hasDefinedIsDiscoverableByPhoneNumberMock = { true }
        self.isDiscoverableByPhoneNumberMock = { isDiscoverableByPhoneNumber }
        let date = self.dateProvider()
        self.lastSetIsDiscoverablyByPhoneNumberAtMock = { date }
    }

    open func setIsDiscoverableByPhoneNumber(_ isDiscoverable: Bool, tx: DBWriteTransaction) {
        setIsDiscoverableByPhoneNumberMock(isDiscoverable)
    }
}

#endif
