//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class ChangePhoneNumberPniManagerTest: XCTestCase {
    private typealias Parameters = ChangePhoneNumberPni.Parameters
    private typealias PendingState = ChangePhoneNumberPni.PendingState
    private typealias GenerateResult = ChangePhoneNumberPni.GeneratePniIdentityResult

    private var identityManagerMock: ChangePhoneNumberPniManagerImpl.Mocks.IdentityManager!
    private var messageSenderMock: ChangePhoneNumberPniManagerImpl.Mocks.MessageSender!
    private var preKeyManagerMock: ChangePhoneNumberPniManagerImpl.Mocks.PreKeyManager!
    private var signedPreKeyStoreMock: ChangePhoneNumberPniManagerImpl.Mocks.SignedPreKeyStore!
    private var tsAccountManagerMock: ChangePhoneNumberPniManagerImpl.Mocks.TSAccountManager!

    private var scheduler: TestScheduler!
    private var db: MockDB!

    private var changeNumberPniManager: ChangePhoneNumberPniManagerImpl!

    public override func setUp() {
        identityManagerMock = .init()
        messageSenderMock = .init()
        preKeyManagerMock = .init()
        signedPreKeyStoreMock = .init()
        tsAccountManagerMock = .init()

        scheduler = .init()
        db = .init()

        changeNumberPniManager = .init(
            schedulers: TestSchedulers(scheduler: scheduler),
            identityManager: identityManagerMock,
            messageSender: messageSenderMock,
            preKeyManager: preKeyManagerMock,
            pniSignedPreKeyStore: signedPreKeyStoreMock,
            tsAccountManager: tsAccountManagerMock
        )
    }

    // MARK: - Generate identity

    func testGenerateIdentity_HappyPath() {
        let e164: E164 = .init("+17735550199")!
        let linkedDeviceIds: [UInt32] = [123]

        messageSenderMock.deviceMessageMocks = [
            .valid(registrationId: 456)
        ]

        scheduler.start()

        let (parameters, pendingState) = generateIdentity(
            forNewE164: e164,
            linkedDeviceIds: linkedDeviceIds
        ).value!.unwrapSuccess

        XCTAssertEqual(parameters.devicePniSignedPreKeys.count, 2)
        XCTAssertEqual(parameters.pniRegistrationIds.count, 2)
        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, 123)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssertEqual(pendingState.newE164, e164)

        XCTAssert(messageSenderMock.deviceMessageMocks.isEmpty)
    }

    /// If one of our linked devices is invalid, per the message sender, we
    /// should skip it and generate identity without parameters for it.
    func testGenerateIdentity_InvalidDevice() {
        let e164: E164 = .init("+17735550199")!
        let linkedDeviceIds: [UInt32] = [123, 1234]

        messageSenderMock.deviceMessageMocks = [
            .valid(registrationId: 456),
            .invalidDevice
        ]

        scheduler.start()

        let (parameters, pendingState) = generateIdentity(
            forNewE164: e164,
            linkedDeviceIds: linkedDeviceIds
        ).value!.unwrapSuccess

        XCTAssertEqual(parameters.devicePniSignedPreKeys.count, 2)
        XCTAssertEqual(parameters.pniRegistrationIds.count, 2)
        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, 123)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssertEqual(pendingState.newE164, e164)

        XCTAssert(messageSenderMock.deviceMessageMocks.isEmpty)
    }

    func testGenerateIdentity_Error() {
        let e164: E164 = .init("+17735550199")!
        let linkedDeviceIds: [UInt32] = [123]

        messageSenderMock.deviceMessageMocks = [
            .error
        ]

        scheduler.start()

        let isFailureResult = generateIdentity(
            forNewE164: e164,
            linkedDeviceIds: linkedDeviceIds
        ).value!.isError

        XCTAssert(isFailureResult)
        XCTAssert(messageSenderMock.deviceMessageMocks.isEmpty)
    }

    // MARK: - Finalize identity

    func testFinalizeIdentity_HappyPath() {
        let e164: E164 = .init("+17745550199")!

        scheduler.start()

        let (_, pendingState) = generateIdentity(
            forNewE164: e164,
            linkedDeviceIds: []
        ).value!.unwrapSuccess

        db.write { transaction in
            changeNumberPniManager.finalizePniIdentity(
                withPendingState: pendingState,
                transaction: transaction
            )
        }

        XCTAssertEqual(
            identityManagerMock.storedKeyPairs,
            [.pni: pendingState.pniIdentityKeyPair]
        )

        XCTAssertEqual(
            signedPreKeyStoreMock.storedSignedPreKeyId,
            pendingState.localDevicePniSignedPreKeyRecord.id
        )
        XCTAssertEqual(
            signedPreKeyStoreMock.storedSignedPreKeyRecord,
            pendingState.localDevicePniSignedPreKeyRecord
        )

        XCTAssertEqual(
            tsAccountManagerMock.storedPniRegistrationId,
            pendingState.localDevicePniRegistrationId
        )

        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.count, 1)
        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.first?.0, .pni)
        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.first?.1, false)
    }

    // MARK: - Helpers

    private func generateIdentity(
        forNewE164 newE164: E164,
        linkedDeviceIds: [UInt32]
    ) -> Guarantee<GenerateResult> {
        let e164: E164 = .init("+17735550199")!
        let aci: ServiceId = .init(UUID())
        let accountId: String = UUID().uuidString

        let localDeviceId: UInt32 = 1

        return db.write { transaction in
            changeNumberPniManager.generatePniIdentity(
                forNewE164: e164,
                localAci: aci,
                localAccountId: accountId,
                localDeviceId: localDeviceId,
                localUserAllDeviceIds: [localDeviceId] + linkedDeviceIds,
                transaction: transaction
            )
        }
    }
}

private extension ChangePhoneNumberPni.GeneratePniIdentityResult {
    var unwrapSuccess: (
        ChangePhoneNumberPni.Parameters,
        ChangePhoneNumberPni.PendingState
    ) {
        guard case let .success(parameters, pendingState) = self else {
            owsFail("Failed to unwrap success!")
        }

        return (parameters, pendingState)
    }

    var isError: Bool {
        guard case .failure = self else {
            return false
        }

        return true
    }
}
