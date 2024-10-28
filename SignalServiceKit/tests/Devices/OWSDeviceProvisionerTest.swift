//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

import LibSignalClient
@testable import SignalServiceKit

private class MockDeviceProvisioningService: DeviceProvisioningService {
    var deviceProvisioningCodes = [String]()
    func requestDeviceProvisioningCode() -> Promise<DeviceProvisioningCodeResponse> {
        return .value(.init(verificationCode: deviceProvisioningCodes.removeFirst(), tokenIdentifier: UUID().uuidString))
    }

    var provisionedDevices = [(messageBody: Data, ephemeralDeviceId: String)]()
    func provisionDevice(messageBody: Data, ephemeralDeviceId: String) -> Promise<Void> {
        provisionedDevices.append((messageBody, ephemeralDeviceId))
        return .value(())
    }
}

class OWSDeviceProvisionerTest: XCTestCase {
    private var mockDeviceProvisioningService: MockDeviceProvisioningService!
    private var schedulers: TestSchedulers!

    override func setUp() {
        super.setUp()

        mockDeviceProvisioningService = MockDeviceProvisioningService()

        schedulers = TestSchedulers(scheduler: TestScheduler())
        schedulers.scheduler.start()
    }

    func testProvisioning() throws {
        let linkedDeviceCipher = ProvisioningCipher.generate()

        let myAciIdentityKeyPair = IdentityKeyPair.generate()
        let myPniIdentityKeyPair = IdentityKeyPair.generate()
        let myAci = Aci.randomForTesting()
        let myPhoneNumber = "+16505550100"
        let myPni = Pni.randomForTesting()
        let profileKey = Randomness.generateRandomBytes(UInt(ProfileKey.SIZE))
        let masterKey = Randomness.generateRandomBytes(SVR.masterKeyLengthBytes)
        let mrbk = Randomness.generateRandomBytes(MediaRootBackupKeyStore.mediaRootBackupKeyLength)
        let readReceiptsEnabled = true

        let provisioner = OWSDeviceProvisioner(
            myAciIdentityKeyPair: myAciIdentityKeyPair,
            myPniIdentityKeyPair: myPniIdentityKeyPair,
            theirPublicKey: linkedDeviceCipher.secondaryDevicePublicKey,
            theirEphemeralDeviceId: "",
            myAci: myAci,
            myPhoneNumber: myPhoneNumber,
            myPni: myPni,
            profileKey: profileKey,
            masterKey: masterKey,
            mrbk: mrbk,
            ephemeralBackupKey: nil,
            readReceiptsEnabled: readReceiptsEnabled,
            provisioningService: mockDeviceProvisioningService,
            schedulers: schedulers
        )

        let provisioningCode = "ABC123"
        mockDeviceProvisioningService.deviceProvisioningCodes.append(provisioningCode)

        try provisioner.provision().done(on: schedulers.sync) { _ in
            let (messageBody, _) = self.mockDeviceProvisioningService.provisionedDevices.removeFirst()
            let provisionEnvelope = try ProvisioningProtoProvisionEnvelope(serializedData: messageBody)
            let provisionMessage = try linkedDeviceCipher.decrypt(envelope: provisionEnvelope)

            XCTAssertEqual(provisionMessage.aci, myAci)
            XCTAssertEqual(provisionMessage.phoneNumber, myPhoneNumber)
            XCTAssertEqual(provisionMessage.pni, myPni)
            XCTAssertEqual(provisionMessage.aciIdentityKeyPair.publicKey, Data(myAciIdentityKeyPair.publicKey.keyBytes))
            XCTAssertEqual(provisionMessage.pniIdentityKeyPair.publicKey, Data(myPniIdentityKeyPair.publicKey.keyBytes))
            XCTAssertEqual(provisionMessage.profileKey.keyData, profileKey)
            XCTAssertEqual(provisionMessage.masterKey, masterKey)
            XCTAssertEqual(provisionMessage.areReadReceiptsEnabled, readReceiptsEnabled)
            XCTAssertEqual(provisionMessage.provisioningCode, provisioningCode)
        }.wait()
    }
}
