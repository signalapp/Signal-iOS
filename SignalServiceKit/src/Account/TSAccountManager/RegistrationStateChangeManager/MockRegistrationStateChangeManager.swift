//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

open class MockRegistrationStateChangeManager: RegistrationStateChangeManager {

    public init() {}

    public var registrationStateMock: (() -> TSRegistrationState) = {
        return .registered
    }

    open func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return registrationStateMock()
    }

    public lazy var didRegisterPrimaryMock: (
        _ e164: E164,
        _ aci: Aci,
        _ pni: Pni,
        _ authToken: String
    ) -> Void = { [weak self] _, _, _, _ in
        self?.registrationStateMock = { .registered }
    }

    open func didRegisterPrimary(
        e164: E164,
        aci: Aci,
        pni: Pni,
        authToken: String,
        tx: DBWriteTransaction
    ) {
        didRegisterPrimaryMock(e164, aci, pni, authToken)
    }

    public lazy var didLinkSecondaryMock: (
        _ e164: E164,
        _ aci: Aci,
        _ pni: Pni?,
        _ authToken: String,
        _ deviceId: UInt32
    ) -> Void = { [weak self] _, _, _, _, _ in
        self?.registrationStateMock = { .linkedButUnprovisioned }
    }

    open func didLinkSecondary(e164: E164, aci: Aci, pni: Pni?, authToken: String, deviceId: UInt32, tx: DBWriteTransaction) {
        didLinkSecondaryMock(e164, aci, pni, authToken, deviceId)
    }

    public lazy var didFinishProvisioningSecondayMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .provisioned }
    }

    open func didFinishProvisioningSecondary(tx: DBWriteTransaction) {
        didFinishProvisioningSecondayMock()
    }

    public var didUpdateLocalPhoneNumberMock: (
        _ e164: E164,
        _ aci: Aci,
        _ pni: Pni?
    ) -> Void = { _, _, _ in }

    open func didUpdateLocalPhoneNumber(_ e164: E164, aci: Aci, pni: Pni?, tx: DBWriteTransaction) {
        didUpdateLocalPhoneNumberMock(e164, aci, pni)
    }

    public lazy var resetForReregistrationMock: (
        _ localPhoneNumber: E164,
        _ localAci: Aci,
        _ wasPrimaryDevice: Bool
    ) -> Void = { [weak self] phoneNumber, aci, _ in
        self?.registrationStateMock = { .reregistering(phoneNumber: phoneNumber.stringValue, aci: aci) }
    }

    open func resetForReregistration(localPhoneNumber: E164, localAci: Aci, wasPrimaryDevice: Bool, tx: DBWriteTransaction) {
        return resetForReregistrationMock(localPhoneNumber, localAci, wasPrimaryDevice)
    }

    public lazy var setIsTransferInProgressMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .transferringIncoming }
    }

    open func setIsTransferInProgress(tx: DBWriteTransaction) {
        setIsTransferInProgressMock()
    }

    public lazy var setIsTransferCompleteMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .registered }
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
        _ isDeregisteredOrDelinked: Bool
    ) -> Void = { [weak self] isDeregisteredOrDelinked in
        let wasPrimary = self?.registrationStateMock().isPrimaryDevice ?? true
        if isDeregisteredOrDelinked {
            self?.registrationStateMock = wasPrimary ? { .deregistered } : { .delinked }
        } else {
            self?.registrationStateMock = wasPrimary ? { .registered } : { .provisioned }
        }
    }

    open func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) {
        setIsDeregisteredOrDelinkedMock(isDeregisteredOrDelinked)
    }

    public var unregisterFromServiceMock: (_ auth: ChatServiceAuth) async throws -> Void = { _ in }

    open func unregisterFromService(auth: ChatServiceAuth) async throws {
        try await unregisterFromServiceMock(auth)
    }
}

#endif
