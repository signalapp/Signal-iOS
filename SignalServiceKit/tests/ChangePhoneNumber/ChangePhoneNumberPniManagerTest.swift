//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class ChangePhoneNumberPniManagerTest: XCTestCase {
    private var identityManagerMock: IdentityManagerMock!
    private var pniDistributionParameterBuilderMock: PniDistributionParameterBuilderMock!
    private var preKeyManagerMock: PreKeyManagerMock!
    private var signedPreKeyStoreMock: MockSignalSignedPreKeyStore!
    private var kyberPreKeyStoreMock: MockKyberPreKeyStore!
    private var registrationIdGeneratorMock: MockRegistrationIdGenerator!
    private var tsAccountManagerMock: MockTSAccountManager!

    private var schedulers: TestSchedulers!
    private var db: MockDB!

    private var changeNumberPniManager: ChangePhoneNumberPniManager!

    public override func setUp() {
        identityManagerMock = .init()
        pniDistributionParameterBuilderMock = .init()
        preKeyManagerMock = .init()
        kyberPreKeyStoreMock = .init(dateProvider: Date.provider)
        signedPreKeyStoreMock = .init()
        registrationIdGeneratorMock = .init()
        tsAccountManagerMock = .init()

        schedulers = TestSchedulers(scheduler: TestScheduler())
        schedulers.scheduler.start()

        db = .init()

        changeNumberPniManager = ChangePhoneNumberPniManagerImpl(
            identityManager: identityManagerMock,
            pniDistributionParameterBuilder: pniDistributionParameterBuilderMock,
            pniSignedPreKeyStore: signedPreKeyStoreMock,
            pniKyberPreKeyStore: kyberPreKeyStoreMock,
            preKeyManager: preKeyManagerMock,
            registrationIdGenerator: registrationIdGeneratorMock,
            schedulers: schedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    // MARK: - Generate identity

    func testGenerateIdentityHappyPath() {
        let e164 = E164("+17735550199")!

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]

        let (parameters, pendingState) = generateIdentity(
            e164: e164,
            linkedDeviceIds: [2, 3]
        ).value!.unwrapSuccess

        XCTAssertEqual(e164, pendingState.newE164)

        XCTAssertEqual(identityManagerMock.generatedKeyPairs.count, 1)
        XCTAssertEqual(identityManagerMock.generatedKeyPairs.first?.publicKey, parameters.pniIdentityKey)
        XCTAssertEqual(identityManagerMock.generatedKeyPairs.first, pendingState.pniIdentityKeyPair)

        XCTAssertEqual(signedPreKeyStoreMock.generatedSignedPreKeys.count, 1)
        XCTAssertEqual(signedPreKeyStoreMock.generatedSignedPreKeys.first, pendingState.localDevicePniSignedPreKeyRecord)

        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.count, 1)
        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.first, pendingState.localDevicePniRegistrationId)

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedForDeviceIds, [[1, 2, 3]])
        XCTAssertTrue(pniDistributionParameterBuilderMock.buildOutcomes.isEmpty)
    }

    func testGenerateIdentityWithError() {
        let e164 = E164("+17735550199")!

        pniDistributionParameterBuilderMock.buildOutcomes = [.failure]

        let isFailureResult = generateIdentity(
            e164: e164,
            linkedDeviceIds: [2, 3]
        ).value!.isError

        XCTAssertTrue(isFailureResult)

        XCTAssertEqual(identityManagerMock.generatedKeyPairs.count, 1)
        XCTAssertEqual(signedPreKeyStoreMock.generatedSignedPreKeys.count, 1)
        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.count, 1)

        XCTAssertEqual(pniDistributionParameterBuilderMock.buildRequestedForDeviceIds, [[1, 2, 3]])
        XCTAssertTrue(pniDistributionParameterBuilderMock.buildOutcomes.isEmpty)
    }

    // MARK: - Finalize identity

    func testFinalizeIdentityHappyPath() {
        let e164 = E164("+17735550199")!

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]

        let (_, pendingState) = generateIdentity(
            e164: e164,
            linkedDeviceIds: [2, 3]
        ).value!.unwrapSuccess

        db.write { transaction in
            try! changeNumberPniManager.finalizePniIdentity(
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
            tsAccountManagerMock.pniRegistrationIdMock(),
            pendingState.localDevicePniRegistrationId
        )

        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.count, 1)
        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.first?.0, .pni)
        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.first?.1, false)
    }

    // MARK: - Helpers

    private func generateIdentity(
        e164: E164,
        linkedDeviceIds: [UInt32]
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult> {
        let aci = Aci.randomForTesting()
        let accountId: String = UUID().uuidString

        let localDeviceId: UInt32 = 1

        return changeNumberPniManager.generatePniIdentity(
            forNewE164: e164,
            localAci: aci,
            localAccountId: accountId,
            localDeviceId: localDeviceId,
            localUserAllDeviceIds: [localDeviceId] + linkedDeviceIds
        )
    }
}

private extension ChangePhoneNumberPni.GeneratePniIdentityResult {
    var unwrapSuccess: (
        PniDistribution.Parameters,
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

// MARK: - Mocks

// MARK: IdentityManager

private class IdentityManagerMock: ChangePhoneNumberPniManagerImpl.Shims.IdentityManager {
    var generatedKeyPairs: [ECKeyPair] = []
    var storedKeyPairs: [OWSIdentity: ECKeyPair] = [:]

    func generateNewIdentityKeyPair() -> ECKeyPair {
        let keyPair = Curve25519.generateKeyPair()
        generatedKeyPairs.append(keyPair)
        return keyPair
    }

    func setIdentityKeyPair(
        _ keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        tx _: DBWriteTransaction
    ) {
        storedKeyPairs[identity] = keyPair
    }
}

// MARK: PreKeyManager

private class PreKeyManagerMock: ChangePhoneNumberPniManagerImpl.Shims.PreKeyManager {
    var attemptedRefreshes: [(OWSIdentity, Bool)] = []

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        attemptedRefreshes.append((identity, shouldRefreshSignedPreKey))
    }
}

// MARK: PniDistributionParameterBuilder

private class PniDistributionParameterBuilderMock: PniDistributionParamaterBuilder {
    enum BuildOutcome {
        case success
        case failure
    }

    var buildOutcomes: [BuildOutcome] = []
    var buildRequestedForDeviceIds: [[UInt32]] = []

    func buildPniDistributionParameters(
        localAci: Aci,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) -> Guarantee<PniDistribution.ParameterGenerationResult> {
        guard let buildOutcome = buildOutcomes.first else {
            XCTFail("Missing build outcome!")
            return .value(.failure)
        }

        buildOutcomes = Array(buildOutcomes.dropFirst())

        buildRequestedForDeviceIds.append(localUserAllDeviceIds)

        switch buildOutcome {
        case .success:
            return .value(.success(PniDistribution.Parameters.mock(
                pniIdentityKeyPair: localPniIdentityKeyPair,
                localDeviceId: localDeviceId,
                localDevicePniSignedPreKey: localDevicePniSignedPreKey,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
                localDevicePniRegistrationId: localDevicePniRegistrationId
            )))
        case .failure:
            return .value(.failure)
        }
    }
}
