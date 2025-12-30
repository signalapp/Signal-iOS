//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

public class MockTSAccountManager: TSAccountManager {

    public init() {}

    public var warmCachesMock: ((DBReadTransaction) -> Void)?

    open func warmCaches(tx: DBReadTransaction) {
        warmCachesMock?(tx)
    }

    // MARK: - Local Identifiers

    public var localIdentifiersMock: (() -> LocalIdentifiers?) = {
        return LocalIdentifiers(
            aci: .randomForTesting(),
            pni: .randomForTesting(),
            e164: .init("+15555555555")!,
        )
    }

    open var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { localIdentifiersMock() }

    open func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return localIdentifiersWithMaybeSneakyTransaction
    }

    public var storedServerUsernameMock: (() -> String?) = { "testAccount" }

    open var storedServerUsernameWithMaybeTransaction: String? { storedServerUsernameMock() }

    open func storedServerUsername(tx: DBReadTransaction) -> String? {
        return storedServerUsernameWithMaybeTransaction
    }

    public var storedServerAuthTokenMock: (() -> String?) = { "authToken" }

    open var storedServerAuthTokenWithMaybeTransaction: String? { storedServerAuthTokenMock() }

    open func storedServerAuthToken(tx: DBReadTransaction) -> String? {
        return storedServerAuthTokenWithMaybeTransaction
    }

    public var storedDeviceIdMock: (() -> LocalDeviceId) = { .valid(.primary) }

    open var storedDeviceIdWithMaybeTransaction: LocalDeviceId { storedDeviceIdMock() }

    open func storedDeviceId(tx: DBReadTransaction) -> LocalDeviceId {
        return storedDeviceIdWithMaybeTransaction
    }

    // MARK: - Registration State

    public var registrationStateMock: (() -> TSRegistrationState) = {
        return .registered
    }

    open var registrationStateWithMaybeSneakyTransaction: TSRegistrationState { registrationStateMock() }

    open func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return registrationStateWithMaybeSneakyTransaction
    }

    public var registrationDateMock: (() -> Date?) = {
        return .distantPast
    }

    open func registrationDate(tx: DBReadTransaction) -> Date? {
        return registrationDateMock()
    }

    // MARK: - RegistrationIds

    public var aciRegistrationIdMock: () -> UInt32 = {
        let id = RegistrationIdGenerator.generate()
        return { id }
    }()

    public var pniRegistrationIdMock: () -> UInt32 = {
        let id = RegistrationIdGenerator.generate()
        return { id }
    }()

    open func getRegistrationId(for identity: OWSIdentity, tx: DBReadTransaction) -> UInt32? {
        switch identity {
        case .aci:
            return aciRegistrationIdMock()
        case .pni:
            return pniRegistrationIdMock()
        }
    }

    open func clearRegistrationIds(tx: DBWriteTransaction) {}

    public lazy var setAciRegistrationIdMock: (_ id: UInt32) -> Void = { [weak self] id in
        self?.aciRegistrationIdMock = { id }
    }

    public lazy var setPniRegistrationIdMock: (_ id: UInt32) -> Void = { [weak self] id in
        self?.pniRegistrationIdMock = { id }
    }

    open func setRegistrationId(_ newRegistrationId: UInt32, for identity: OWSIdentity, tx: DBWriteTransaction) {
        switch identity {
        case .aci:
            setAciRegistrationIdMock(newRegistrationId)
        case .pni:
            setPniRegistrationIdMock(newRegistrationId)
        }
    }

    // MARK: - Manual Message Fetch

    public var isManualMessageFetchEnabledMock: () -> Bool = { false }

    open func isManualMessageFetchEnabled(tx: DBReadTransaction) -> Bool {
        return isManualMessageFetchEnabledMock()
    }

    public lazy var setIsManualMessageFetchEnabledMock: (
        Bool,
    ) -> Void = { [weak self] isManualMessageFetchEnabled in
        self?.isManualMessageFetchEnabledMock = { isManualMessageFetchEnabled }
    }

    open func setIsManualMessageFetchEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
        setIsManualMessageFetchEnabledMock(isEnabled)
    }

    // MARK: - Phone Number Discoverability

    public var phoneNumberDiscoverabilityMock: () -> PhoneNumberDiscoverability? = { .everybody }

    open func phoneNumberDiscoverability(tx: DBReadTransaction) -> PhoneNumberDiscoverability? {
        return phoneNumberDiscoverabilityMock()
    }

    public var lastSetIsDiscoverableByPhoneNumberMock: () -> Date = { .distantPast }

    open func lastSetIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Date {
        return lastSetIsDiscoverableByPhoneNumberMock()
    }
}

#endif
