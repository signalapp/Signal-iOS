//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class MockTSAccountManager: TSAccountManagerProtocol {

    public var dateProvider: DateProvider

    public init(dateProvider: @escaping DateProvider = { Date() }) {
        self.dateProvider = dateProvider
    }

    public func tmp_loadAccountState(tx: DBReadTransaction) {}

    public var warmCachesMock: (() -> Void)?

    open func warmCaches() {
        warmCachesMock?()
    }

    // MARK: - Local Identifiers

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

    public var storedDeviceIdMock: (() -> UInt32) = { 1 }

    open var storedDeviceIdWithMaybeTransaction: UInt32 { storedDeviceIdMock() }

    open func storedDeviceId(tx: DBReadTransaction) -> UInt32 {
        return storedDeviceIdWithMaybeTransaction
    }

    // MARK: - Registration State

    public var registrationStateMock: (() -> TSRegistrationState) = {
        return .registered
    }

    public var registrationStateWithMaybeSneakyTransaction: TSRegistrationState { registrationStateMock() }

    public func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return registrationStateWithMaybeSneakyTransaction
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

    public lazy var setPniRegistrationIdMock: (_ id: UInt32) -> Void = { [weak self] id in
        self?.pniRegistrationIdMock = { id }
    }

    open func setPniRegistrationId(_ newRegistrationId: UInt32, tx: DBWriteTransaction) {
        setPniRegistrationIdMock(newRegistrationId)
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
}
