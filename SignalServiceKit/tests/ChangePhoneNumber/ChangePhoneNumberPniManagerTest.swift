//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ChangePhoneNumberPniManagerTest: XCTestCase {
    private var identityManagerMock: IdentityManagerMock!
    private var pniDistributionParameterBuilderMock: PniDistributionParameterBuilderMock!
    private var preKeyManagerMock: PreKeyManagerMock!
    private var signedPreKeyStoreMock: SignedPreKeyStoreImpl!
    private var kyberPreKeyStoreMock: KyberPreKeyStoreImpl!
    private var registrationIdGeneratorMock: MockRegistrationIdGenerator!
    private var tsAccountManagerMock: MockTSAccountManager!

    private var db: InMemoryDB!

    private var changeNumberPniManager: ChangePhoneNumberPniManager!

    public override func setUp() {
        identityManagerMock = .init()
        pniDistributionParameterBuilderMock = .init()
        preKeyManagerMock = .init()
        kyberPreKeyStoreMock = .init(for: .pni, dateProvider: Date.provider)
        signedPreKeyStoreMock = .init(for: .pni)
        registrationIdGeneratorMock = .init()
        tsAccountManagerMock = .init()

        db = .init()

        changeNumberPniManager = ChangePhoneNumberPniManagerImpl(
            db: db,
            identityManager: identityManagerMock,
            pniDistributionParameterBuilder: pniDistributionParameterBuilderMock,
            pniSignedPreKeyStore: signedPreKeyStoreMock,
            pniKyberPreKeyStore: kyberPreKeyStoreMock,
            preKeyManager: preKeyManagerMock,
            registrationIdGenerator: registrationIdGeneratorMock,
            tsAccountManager: tsAccountManagerMock
        )
    }

    // MARK: - Generate identity

    func testGenerateIdentityHappyPath() async {
        let e164 = E164("+17735550199")!

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]

        let (parameters, pendingState) = await generateIdentity(e164: e164).unwrapSuccess

        XCTAssertEqual(e164, pendingState.newE164)

        XCTAssertEqual(identityManagerMock.generatedKeyPairs.count, 1)
        XCTAssertEqual(identityManagerMock.generatedKeyPairs.first?.keyPair.identityKey, parameters.pniIdentityKey)
        XCTAssertEqual(identityManagerMock.generatedKeyPairs.first, pendingState.pniIdentityKeyPair)

        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.count, 1)
        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.first, pendingState.localDevicePniRegistrationId)

        XCTAssertTrue(pniDistributionParameterBuilderMock.buildOutcomes.isEmpty)
    }

    func testGenerateIdentityWithError() async {
        let e164 = E164("+17735550199")!

        pniDistributionParameterBuilderMock.buildOutcomes = [.failure]

        let isFailureResult = await generateIdentity(e164: e164).isError

        XCTAssertTrue(isFailureResult)

        XCTAssertEqual(identityManagerMock.generatedKeyPairs.count, 1)
        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.count, 1)

        XCTAssertTrue(pniDistributionParameterBuilderMock.buildOutcomes.isEmpty)
    }

    // MARK: - Finalize identity

    func testFinalizeIdentityHappyPath() async {
        let e164 = E164("+17735550199")!

        pniDistributionParameterBuilderMock.buildOutcomes = [.success]

        let (_, pendingState) = await generateIdentity(e164: e164).unwrapSuccess

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

        db.read { tx in
            XCTAssertNotNil(signedPreKeyStoreMock.loadSignedPreKey(pendingState.localDevicePniSignedPreKeyRecord.id, transaction: tx))
        }

        XCTAssertEqual(
            tsAccountManagerMock.pniRegistrationIdMock(),
            pendingState.localDevicePniRegistrationId
        )

        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.count, 1)
        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.first?.0, .pni)
        XCTAssertEqual(preKeyManagerMock.attemptedRefreshes.first?.1, false)
    }

    // MARK: - Helpers

    private func generateIdentity(e164: E164) async -> ChangePhoneNumberPni.GeneratePniIdentityResult {
        let aci = Aci.randomForTesting()
        let localDeviceId: DeviceId = .primary

        return await changeNumberPniManager.generatePniIdentity(
            forNewE164: e164,
            localAci: aci,
            localDeviceId: localDeviceId
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

final private class IdentityManagerMock: ChangePhoneNumberPniManagerImpl.Shims.IdentityManager {
    var generatedKeyPairs: [ECKeyPair] = []
    var storedKeyPairs: [OWSIdentity: ECKeyPair] = [:]

    func generateNewIdentityKeyPair() -> ECKeyPair {
        let keyPair = ECKeyPair.generateKeyPair()
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

final private class PreKeyManagerMock: ChangePhoneNumberPniManagerImpl.Shims.PreKeyManager {
    var attemptedRefreshes: [(OWSIdentity, Bool)] = []

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        attemptedRefreshes.append((identity, shouldRefreshSignedPreKey))
    }
}

// MARK: PniDistributionParameterBuilder

final private class PniDistributionParameterBuilderMock: PniDistributionParamaterBuilder {
    enum BuildOutcome {
        case success
        case failure
    }

    var buildOutcomes: [BuildOutcome] = []

    func buildPniDistributionParameters(
        localAci: Aci,
        localDeviceId: LocalDeviceId,
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) async throws -> PniDistribution.Parameters {
        let buildOutcome = buildOutcomes.first!
        buildOutcomes = Array(buildOutcomes.dropFirst())

        switch buildOutcome {
        case .success:
            return PniDistribution.Parameters.mock(
                pniIdentityKeyPair: localPniIdentityKeyPair,
                localDeviceId: localDeviceId.ifValid!,
                localDevicePniSignedPreKey: localDevicePniSignedPreKey,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
                localDevicePniRegistrationId: localDevicePniRegistrationId
            )
        case .failure:
            throw OWSGenericError("")
        }
    }
}
