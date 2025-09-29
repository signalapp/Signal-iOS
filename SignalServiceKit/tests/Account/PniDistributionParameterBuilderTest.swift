//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class PniDistributionParameterBuilderTest: XCTestCase {
    private var messageSenderMock: MessageSenderMock!
    private var pniKyberPreKeyStoreMock: KyberPreKeyStoreImpl!
    private var registrationIdGeneratorMock: MockRegistrationIdGenerator!

    private var dateProvider: DateProvider!
    private var db: (any DB)!

    private var pniDistributionParameterBuilder: PniDistributionParameterBuilderImpl!

    override func setUp() {
        dateProvider = { Date() }
        db = InMemoryDB()
        messageSenderMock = .init(db: db)
        pniKyberPreKeyStoreMock = KyberPreKeyStoreImpl(for: .pni, dateProvider: dateProvider)
        registrationIdGeneratorMock = .init()

        pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            db: db,
            messageSender: messageSenderMock,
            pniKyberPreKeyStore: pniKyberPreKeyStoreMock,
            registrationIdGenerator: registrationIdGeneratorMock
        )
    }

    private func buildDeviceMessage(deviceId: DeviceId, registrationId: UInt32) -> DeviceMessage {
        return DeviceMessage(
            type: .ciphertext,
            destinationDeviceId: deviceId,
            destinationRegistrationId: registrationId,
            content: Data()
        )
    }

    func testBuildParametersHappyPath() async throws {
        let pniKeyPair = ECKeyPair.generateKeyPair()
        let localSignedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = registrationIdGeneratorMock.generate()
        let localPqLastResortPreKey = db.write { tx in
            self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessagesMocks.update {
            $0.append(.success([
                buildDeviceMessage(deviceId: DeviceId(validating: 123)!, registrationId: 456),
            ]))
        }

        let parameters = try await build(
            localDeviceId: DeviceId(validating: 1)!,
            localPniIdentityKeyPair: pniKeyPair,
            localDevicePniSignedPreKey: localSignedPreKey,
            localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
            localDevicePniRegistrationId: localRegistrationId
        )

        XCTAssertEqual(parameters.pniIdentityKey, pniKeyPair.keyPair.identityKey)

        XCTAssertEqual(Set(parameters.devicePniSignedPreKeys.values.map { $0.keyPair.publicKey }).count, 2)

        XCTAssertEqual(Set(parameters.devicePniPqLastResortPreKeys.values.map { $0.keyPair.publicKey.serialize() }).count, 2)

        XCTAssertEqual(
            Set(parameters.pniRegistrationIds.values),
            Set(registrationIdGeneratorMock.generatedRegistrationIds)
        )

        XCTAssertEqual(parameters.deviceMessages.count, 1)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationDeviceId, DeviceId(validating: 123)!)
        XCTAssertEqual(parameters.deviceMessages.first?.destinationRegistrationId, 456)

        XCTAssertTrue(messageSenderMock.deviceMessagesMocks.get().isEmpty)
    }

    func testBuildParametersWithError() async {
        let pniKeyPair = ECKeyPair.generateKeyPair()
        let localSignedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(signedBy: pniKeyPair)
        let localRegistrationId = registrationIdGeneratorMock.generate()
        let localPqLastResortPreKey = db.write { tx in
            self.pniKyberPreKeyStoreMock.generateLastResortKyberPreKey(signedBy: pniKeyPair, tx: tx)
        }

        messageSenderMock.deviceMessagesMocks.update {
            $0.append(.failure(OWSGenericError("Arbitrary failure.")))
        }

        let result = await Result {
            return try await build(
                localDeviceId: DeviceId(validating: 1)!,
                localPniIdentityKeyPair: pniKeyPair,
                localDevicePniSignedPreKey: localSignedPreKey,
                localDevicePniPqLastResortPreKey: localPqLastResortPreKey,
                localDevicePniRegistrationId: localRegistrationId
            )
        }

        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(registrationIdGeneratorMock.generatedRegistrationIds.count, 1)
        XCTAssert(messageSenderMock.deviceMessagesMocks.get().isEmpty)
    }

    // MARK: Helpers

    private func build(
        localDeviceId: DeviceId,
        localPniIdentityKeyPair: ECKeyPair,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) async throws -> PniDistribution.Parameters {
        let aci = Aci.randomForTesting()
        let e164 = E164("+17735550199")!

        return try await pniDistributionParameterBuilder.buildPniDistributionParameters(
            localAci: aci,
            localDeviceId: .valid(localDeviceId),
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

final private class MessageSenderMock: PniDistributionParameterBuilderImpl.Shims.MessageSender {
    private let db: any DB
    init(db: any DB) {
        self.db = db
    }

    /// Populated with device messages to be returned by ``buildDeviceMessages``.
    let deviceMessagesMocks: AtomicValue<[Result<[DeviceMessage], any Error>]> = .init([], lock: .init())

    func buildDeviceMessages(
        serviceId: ServiceId,
        isSelfSend: Bool,
        encryptionStyle: EncryptionStyle,
        buildPlaintextContent: (DeviceId, DBWriteTransaction) throws -> Data,
        isTransient: Bool,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [DeviceMessage] {
        let nextResult = deviceMessagesMocks.update { $0.removeFirst() }
        let result = try nextResult.get()
        try await self.db.awaitableWrite { tx in
            try result.forEach { _ = try buildPlaintextContent($0.destinationDeviceId, tx) }
        }
        return result
    }
}
