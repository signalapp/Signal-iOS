//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient

open class MockRegistrationStateChangeManager: RegistrationStateChangeManager {

    public init() {}

    public var registrationStateMock: (() -> TSRegistrationState) = {
        owsFail("not implemented")
    }

    open func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return registrationStateMock()
    }

    public lazy var didRegisterOrProvisionMock: (
        _ aci: Aci,
        _ phoneNumber: LocalIdentifiers.PhoneNumber,
        _ authToken: String,
        _ deviceId: DeviceId,
    ) -> Void = { [weak self] aci, phoneNumber, _, _ in
        self?.registrationStateMock = { .registered(LocalIdentifiers(aci: aci, phoneNumber: phoneNumber)) }
    }

    open func didRegisterOrProvision(
        aci: Aci,
        phoneNumber: LocalIdentifiers.PhoneNumber,
        authToken: String,
        deviceId: DeviceId,
        tx: DBWriteTransaction,
    ) {
        didRegisterOrProvisionMock(aci, phoneNumber, authToken, deviceId)
    }

    public var didUpdateLocalPhoneNumberMock: (
        _ aci: Aci,
        _ phoneNumber: LocalIdentifiers.PhoneNumber,
    ) -> Void = { _, _ in }

    public func didUpdateLocalPhoneNumber(aci: Aci, phoneNumber: LocalIdentifiers.PhoneNumber, tx: DBWriteTransaction) {
        didUpdateLocalPhoneNumberMock(aci, phoneNumber)
    }

    public lazy var resetForReregistrationMock: (
        _ aci: Aci?,
        _ phoneNumber: E164,
        _ isPrimaryDevice: Bool,
    ) -> Void = { [weak self] aci, phoneNumber, _ in
        self?.registrationStateMock = { .reregistering(ReregisteringLocalIdentifiers(phoneNumber: phoneNumber.stringValue, aci: aci)) }
    }

    open func resetForReregistration(
        aci: Aci?,
        phoneNumber: E164,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction,
    ) {
        return resetForReregistrationMock(aci, phoneNumber, isPrimaryDevice)
    }

    public lazy var setIsTransferInProgressMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .transferringIncoming }
    }

    open func setIsTransferInProgress(tx: DBWriteTransaction) {
        setIsTransferInProgressMock()
    }

    public lazy var setIsTransferCompleteMock: () -> Void = { [weak self] in
        owsFail("not implemented")
    }

    open func setIsTransferComplete(sendStateUpdateNotification: Bool, tx: DBWriteTransaction) {
        setIsTransferCompleteMock()
    }

    public lazy var setWasTransferredMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .transferred }
    }

    open func setWasTransferred(tx: DBWriteTransaction) {
        setWasTransferredMock()
    }

    public var cleanUpTransferStateOnAppLaunchIfNeededMock: () -> Void = {}

    open func cleanUpTransferStateOnAppLaunchIfNeeded() {
        cleanUpTransferStateOnAppLaunchIfNeededMock()
    }

    public lazy var setIsDeregisteredOrDelinkedMock: (
        _ isDeregisteredOrDelinked: Bool,
    ) -> Void = { _ in
        owsFail("not implemented")
    }

    open func setIsDeregisteredOrDelinked(
        _ isDeregisteredOrDelinked: Bool,
        notify: Bool,
        tx: DBWriteTransaction,
    ) {
        setIsDeregisteredOrDelinkedMock(isDeregisteredOrDelinked)
    }

    public var unregisterFromServiceMock: () async throws -> Void = { fatalError() }

    open func unregisterFromService() async throws {
        try await unregisterFromServiceMock()
    }

    public func unlinkLocalDevice(localDeviceId: LocalDeviceId, auth: ChatServiceAuth) async throws { fatalError() }
}

#endif
