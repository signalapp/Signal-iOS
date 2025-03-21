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
    private var registrationIdGeneratorMock: MockRegistrationIdGenerator!

    private var dateProvider: DateProvider!
    private var db: (any DB)!

    private var pniDistributionParameterBuilder: PniDistributionParameterBuilderImpl!

    override func setUp() {
        dateProvider = { Date() }
        messageSenderMock = .init()
        pniSignedPreKeyStoreMock = MockSignalSignedPreKeyStore()
        pniKyberPreKeyStoreMock = MockKyberPreKeyStore(dateProvider: dateProvider)
        registrationIdGeneratorMock = .init()
        db = InMemoryDB()

        pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            db: db,
            messageSender: messageSenderMock,
            pniSignedPreKeyStore: pniSignedPreKeyStoreMock,
            pniKyberPreKeyStore: pniKyberPreKeyStoreMock,
            registrationIdGenerator: registrationIdGeneratorMock
        )
    }

    func testBuildParametersHappyPath() async throws {
        let pniKeyPair = ECKeyPair.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = registrationIdGeneratorMock.generate()
        let localPqLastResortPreKey = db.write { tx in
            self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks.update {
            $0[DeviceId(rawValue: 123)] = .valid(registrationId: 456)
        }

        let parameters = try await build(
            localDeviceId: DeviceId(rawValue: 1),
            localUserAllDeviceIds: [1, 123].map(DeviceId.init(rawValue:)),
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        )

        XCTAssertEqual(parameters.pniIdentityKey, pniKeyPair.keyPair.identityKey)

        XCTAssertEqual(
            Set(parameters.devicePniSignedPreKeys.values.map(\.id)),
            Set(pniSignedPreKeyStoreMock.generatedSignedPreKeys.map(\.id))
        )

        XCTAssertEqual(
            Set(parameters.devicePniPqLastResortPreKeys.values.map(\.id)),
            Set(pniKyberPreKeyStoreMock.lastResortRecords.map(\.id))
        )

        XCTAssertEqual(
            Set(parameters.pniRegistrationIds.values),
            Set(registrationIdGeneratorMock.generatedRegistrationIds)
        )

        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, DeviceId(rawValue: 123))
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssertTrue(messageSenderMock.deviceMessageMocks.get().isEmpty)
    }

    func testBuildParametersFailsBeforeMessageBuildingIfDeviceIdsMismatched() async {
        let pniKeyPair = ECKeyPair.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = registrationIdGeneratorMock.generate()
        let localPqLastResortPreKey = db.write { tx in
            self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks.update {
            $0[DeviceId(rawValue: 123)] = .valid(registrationId: 456)
        }

        let result = await Result {
            return try await build(
                localDeviceId: DeviceId(rawValue: 1),
                localUserAllDeviceIds: [2, 123].map(DeviceId.init(rawValue:)),
                localPniIdentityKeyPair: pniKeyPair,
                localDevicePniSignedPreKey: localSignedPreKey,
                localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
                localDevicePniRegistrationId: localRegistrationId
            )
        }
        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(messageSenderMock.deviceMessageMocks.get().count, 1)
    }

    /// If one of our linked devices is invalid, per the message sender, we
    /// should skip it and generate identity without parameters for it.
    func testBuildParametersWithInvalidDevice() async throws {
        let pniKeyPair = ECKeyPair.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = registrationIdGeneratorMock.generate()
        let localPqLastResortPreKey = db.write { tx in
            self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks.update {
            $0[DeviceId(rawValue: 123)] = .valid(registrationId: 456)
            $0[DeviceId(rawValue: 1234)] = .invalidDevice
        }

        let parameters = try await build(
            localDeviceId: DeviceId(rawValue: 1),
            localUserAllDeviceIds: [1, 123, 1234].map(DeviceId.init(rawValue:)),
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        )

        XCTAssertEqual(parameters.pniIdentityKey, pniKeyPair.keyPair.identityKey)

        // We should have generated a pre-key we threw away, for the invalid
        // device.
        XCTAssertLessThan(parameters.devicePniSignedPreKeys.count, pniSignedPreKeyStoreMock.generatedSignedPreKeys.count)

        // We should have generated a registration ID we threw away, for the
        // invalid device.
        XCTAssertLessThan(parameters.pniRegistrationIds.count, registrationIdGeneratorMock.generatedRegistrationIds.count)

        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, DeviceId(rawValue: 123))
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssert(messageSenderMock.deviceMessageMocks.get().isEmpty)
    }

    func testBuildParametersWithError() async {
        let pniKeyPair = ECKeyPair.generateKeyPair()
        let localSignedPreKey = pniSignedPreKeyStoreMock.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = registrationIdGeneratorMock.generate()
        let localPqLastResortPreKey = db.write { tx in
            self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessageMocks.update {
            $0[DeviceId(rawValue: 123)] = .error
        }

        let result = await Result {
            return try await build(
                localDeviceId: DeviceId(rawValue: 1),
                localUserAllDeviceIds: [1, 123].map(DeviceId.init(rawValue:)),
                localPniIdentityKeyPair: pniKeyPair,
                localDevicePniSignedPreKey: localSignedPreKey,
                localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
                localDevicePniRegistrationId: localRegistrationId
            )
        }

        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(pniSignedPreKeyStoreMock.generatedSignedPreKeys.count, 2)
        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.count, 2)
        XCTAssert(messageSenderMock.deviceMessageMocks.get().isEmpty)
    }

    // MARK: Helpers

    private func build(
        localDeviceId: DeviceId,
        localUserAllDeviceIds: [DeviceId],
        localPniIdentityKeyPair: ECKeyPair,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) async throws -> PniDistribution.Parameters {
        let aci = Aci.randomForTesting()
        let recipientUniqueId = "what's up"
        let e164 = E164("+17735550199")!

        return try await pniDistributionParameterBuilder.buildPniDistributionParameters(
            localAci: aci,
            localRecipientUniqueId: recipientUniqueId,
            localDeviceId: localDeviceId,
            localUserAllDeviceIds: localUserAllDeviceIds,
            localPniIdentityKeyPair: localPniIdentityKeyPair,
            localE164: e164,
            localDevicePniSignedPreKey: localDevicePniSignedPreKey,
            localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
            localDevicePniRegistrationId: localDevicePniRegistrationId
        )
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
    let deviceMessageMocks: AtomicValue<[DeviceId: DeviceMessageMock]> = .init([:], lock: .init())

    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data,
        messageEncryptionStyle: EncryptionStyle,
        recipientUniqueId: String,
        serviceId: ServiceId,
        deviceId: DeviceId,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isResendRequestMessage: Bool,
        sealedSenderParameters: SealedSenderParameters?
    ) throws -> DeviceMessage? {
        let nextDeviceMessageMock = deviceMessageMocks.update(block: {
            return $0.removeValue(forKey: deviceId)
        })!

        switch nextDeviceMessageMock {
        case let .valid(registrationId):
            return DeviceMessage(
                type: .ciphertext,
                destinationDeviceId: deviceId,
                destinationRegistrationId: registrationId,
                content: Randomness.generateRandomBytes(32)
            )
        case .invalidDevice:
            return nil
        case .error:
            throw BuildDeviceMessageError()
        }
    }
}
