//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class PniDistributionParameterBuilderTest: XCTestCase {
    private var messageSenderMock: MessageSenderMock!
    private var pniSignedPreKeyStoreMock: MockSignalSignedPreKeyStore!
    private var pniKyberPreKeyStoreMock: MockKyberPreKeyStore!
    private var tsAccountManagerMock: TSAccountManagerMock!

    private var dateProvider: DateProvider!
    private var schedulers: TestSchedulers!
    private var db: DB!

    private var pniDistributionParameterBuilder: PniDistributionParameterBuilderImpl!

    override func setUp() {
        dateProvider = { Date() }
        messageSenderMock = .init()
        pniSignedPreKeyStoreMock = MockSignalSignedPreKeyStore()
        pniKyberPreKeyStoreMock = MockKyberPreKeyStore(dateProvider: dateProvider)
        tsAccountManagerMock = .init()
        db = MockDB()

        schedulers = TestSchedulers(scheduler: TestScheduler())
        schedulers.scheduler.start()

        pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            messageSender: messageSenderMock,
            pniSignedPreKeyStore: pniSignedPreKeyStoreMock,
            pniKyberPreKeyStore: pniKyberPreKeyStoreMock,
            schedulers: schedulers,
            db: db,
            tsAccountManager: tsAccountManagerMock
        )
    }

    func testBuildParametersHappyPath() {
        let pniKeyPair = Curve25519.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = tsAccountManagerMock.generateRegistrationId()
        let localPqLastResortPreKey = try! db.write { tx in
            try self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks = [
            .valid(registrationId: 456)
        ]

        let parameters = build(
            localDeviceId: 1,
            localUserAllDeviceIds: [1, 123],
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        ).value!.unwrapSuccess

        XCTAssertEqual(parameters.pniIdentityKey, pniKeyPair.publicKey)

        XCTAssertEqual(
            Set(parameters.devicePniSignedPreKeys.values),
            Set(pniSignedPreKeyStoreMock.generatedSignedPreKeys)
        )

        XCTAssertEqual(
            Set(parameters.devicePniPqLastResortPreKeys.values),
            Set(pniKyberPreKeyStoreMock.lastResortRecords)
        )

        XCTAssertEqual(
            Set(parameters.pniRegistrationIds.values),
            Set(tsAccountManagerMock.generatedRegistrationIds)
        )

        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, 123)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssertTrue(messageSenderMock.deviceMessageMocks.isEmpty)
    }

    func testBuildParametersFailsBeforeMessageBuildingIfDeviceIdsMismatched() {
        let pniKeyPair = Curve25519.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = tsAccountManagerMock.generateRegistrationId()
        let localPqLastResortPreKey = try! db.write { tx in
            try self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks = [
            .valid(registrationId: 456)
        ]

        let isFailureResult = build(
            localDeviceId: 1,
            localUserAllDeviceIds: [2, 123],
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        ).value!.isError

        XCTAssertTrue(isFailureResult)
        XCTAssertEqual(messageSenderMock.deviceMessageMocks.count, 1)
    }

    /// If one of our linked devices is invalid, per the message sender, we
    /// should skip it and generate identity without parameters for it.
    func testBuildParametersWithInvalidDevice() {
        let pniKeyPair = Curve25519.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = tsAccountManagerMock.generateRegistrationId()
        let localPqLastResortPreKey = try! db.write { tx in
            try self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks = [
            .valid(registrationId: 456),
            .invalidDevice
        ]

        let parameters = build(
            localDeviceId: 1,
            localUserAllDeviceIds: [1, 123, 1234],
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        ).value!.unwrapSuccess

        XCTAssertEqual(parameters.pniIdentityKey, pniKeyPair.publicKey)

        // We should have generated a pre-key we threw away, for the invalid
        // device.
        XCTAssertLessThan(parameters.devicePniSignedPreKeys.count, pniSignedPreKeyStoreMock.generatedSignedPreKeys.count)

        // We should have generated a registration ID we threw away, for the
        // invalid device.
        XCTAssertLessThan(parameters.pniRegistrationIds.count, tsAccountManagerMock.generatedRegistrationIds.count)

        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, 123)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssert(messageSenderMock.deviceMessageMocks.isEmpty)
    }

    func testBuildParametersWithError() {
        let pniKeyPair = Curve25519.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = tsAccountManagerMock.generateRegistrationId()
        let localPqLastResortPreKey = try! db.write { tx in
            try self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks = [
            .error
        ]

        let isFailureResult = build(
            localDeviceId: 1,
            localUserAllDeviceIds: [1, 123],
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        ).value!.isError

        XCTAssert(isFailureResult)
        XCTAssertEqual(pniSignedPreKeyStoreMock.generatedSignedPreKeys.count, 2)
        XCTAssertEqual(tsAccountManagerMock.generatedRegistrationIds.count, 2)
        XCTAssert(messageSenderMock.deviceMessageMocks.isEmpty)
    }

    // MARK: Helpers

    private func build(
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        localPniIdentityKeyPair: ECKeyPair,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) -> Guarantee<PniDistribution.ParameterGenerationResult> {
        let aci = FutureAci.randomForTesting()
        let accountId = "what's up"

        return pniDistributionParameterBuilder.buildPniDistributionParameters(
            localAci: aci,
            localAccountId: accountId,
            localDeviceId: localDeviceId,
            localUserAllDeviceIds: localUserAllDeviceIds,
            localPniIdentityKeyPair: localPniIdentityKeyPair,
            localDevicePniSignedPreKey: localDevicePniSignedPreKey,
            localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
            localDevicePniRegistrationId: localDevicePniRegistrationId
        )
    }
}

private extension PniDistribution.ParameterGenerationResult {
    var unwrapSuccess: PniDistribution.Parameters {
        switch self {
        case .success(let parameters):
            return parameters
        case .failure:
            owsFail("Unwrapped failed result!")
        }
    }

    var isError: Bool {
        switch self {
        case .success: return false
        case .failure: return true
        }
    }
}

// MARK: - Mocks

// MARK: - MessageSender

private class MessageSenderMock: PniDistributionParameterBuilderImpl.Shims.MessageSender {
    enum DeviceMessageMock {
        case valid(registrationId: UInt32)
        case invalidDevice
        case error
    }

    private struct BuildDeviceMessageError: Error {}

    /// Populated with device messages to be returned by ``buildDeviceMessage``.
    var deviceMessageMocks: [DeviceMessageMock] = []

    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data,
        messageEncryptionStyle: EncryptionStyle,
        recipientId: String,
        serviceId: UntypedServiceId,
        deviceId: UInt32,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
        isResendRequestMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) throws -> DeviceMessage? {
        guard let nextDeviceMessageMock = deviceMessageMocks.first else {
            XCTFail("Missing mock!")
            return nil
        }

        deviceMessageMocks = Array(deviceMessageMocks.dropFirst())

        switch nextDeviceMessageMock {
        case let .valid(registrationId):
            return DeviceMessage(
                type: .ciphertext,
                destinationDeviceId: deviceId,
                destinationRegistrationId: registrationId,
                serializedMessage: Cryptography.generateRandomBytes(32)
            )
        case .invalidDevice:
            return nil
        case .error:
            throw BuildDeviceMessageError()
        }
    }
}

// MARK: TSAccountManager

private class TSAccountManagerMock: PniDistributionParameterBuilderImpl.Shims.TSAccountManager {
    var generatedRegistrationIds: [UInt32] = []

    func generateRegistrationId() -> UInt32 {
        let registrationId = UInt32.random(in: 0..<500)
        generatedRegistrationIds.append(registrationId)
        return registrationId
    }
}
