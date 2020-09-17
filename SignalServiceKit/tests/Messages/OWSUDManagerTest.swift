//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import Curve25519Kit
import SignalCoreKit
import SignalMetadataKit
@testable import SignalServiceKit

class OWSUDManagerTest: SSKBaseTestSwift {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private var udManager: OWSUDManagerImpl {
        return SSKEnvironment.shared.udManager as! OWSUDManagerImpl
    }

    private var profileManager: OWSFakeProfileManager {
        return SSKEnvironment.shared.profileManager as! OWSFakeProfileManager
    }

    // MARK: - Setup/Teardown

    let aliceE164 = "+13213214321"
    let aliceUuid = UUID()
    lazy var aliceAddress = SignalServiceAddress(uuid: aliceUuid, phoneNumber: aliceE164)
    lazy var defaultSenderCert = try! SMKSenderCertificate(serializedData: buildSenderCertificateProto(uuidOnly: false).serializedData())
    lazy var uuidOnlySenderCert = try! SMKSenderCertificate(serializedData: buildSenderCertificateProto(uuidOnly: true).serializedData())

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: aliceE164, uuid: aliceUuid)

        // Configure UDManager
        self.write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData,
                                                  for: self.aliceAddress,
                                                  wasLocallyInitiated: true,
                                                  transaction: transaction)
        }

        udManager.certificateValidator = MockCertificateValidator()
        udManager.setSenderCertificate(uuidOnly: true, certificateData: uuidOnlySenderCert.serializedData)
        udManager.setSenderCertificate(uuidOnly: false, certificateData: defaultSenderCert.serializedData)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // MARK: - Tests

    func testMode_self() {
        XCTAssert(udManager.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        do {
            let udAccess = udManager.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.unknown, address: aliceAddress)
            let udAccess = udManager.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.disabled, address: aliceAddress)
            let udAccess = udManager.udAccess(forAddress: localAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            udManager.setUnidentifiedAccessMode(.enabled, address: aliceAddress)
            let udAccess = udManager.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.unrestricted, address: aliceAddress)
            let udAccess = udManager.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unrestricted, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }
    }

    func testMode_noProfileKey() {
        XCTAssert(udManager.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, address: localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        self.read { transaction in
            XCTAssertNil(self.profileManager.profileKeyData(for: bobRecipientAddress, transaction: transaction))
        }

        do {
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.unknown, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.disabled, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            udManager.setUnidentifiedAccessMode(.enabled, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            // Bob should work in unrestricted mode, even if he doesn't have a profile key.
            udManager.setUnidentifiedAccessMode(.unrestricted, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unrestricted, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }
    }

    func testMode_withProfileKey() {
        XCTAssert(udManager.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, address: localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        self.write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData,
                                                  for: bobRecipientAddress,
                                                  wasLocallyInitiated: true,
                                                  transaction: transaction)
        }

        do {
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.unknown, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)

        }

        do {
            udManager.setUnidentifiedAccessMode(.disabled, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            udManager.setUnidentifiedAccessMode(.enabled, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManager.setUnidentifiedAccessMode(.unrestricted, address: bobRecipientAddress)
            let udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unrestricted, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }
    }

    func test_senderAccess() {
        XCTAssert(udManager.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, address: localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData,
                                                  for: bobRecipientAddress,
                                                  wasLocallyInitiated: true,
                                                  transaction: transaction)
        }

        let completed = self.expectation(description: "completed")
        udManager.ensureSenderCertificates(certificateExpirationPolicy: .strict).done { senderCertificates in
            do {
                let sendingAccess = self.udManager.udSendingAccess(forAddress: bobRecipientAddress, requireSyncAccess: false, senderCertificates: senderCertificates)!
                XCTAssertEqual(.unknown, sendingAccess.udAccess.udAccessMode)
                XCTAssertFalse(sendingAccess.udAccess.isRandomKey)
                XCTAssertEqual(sendingAccess.senderCertificate.serializedData, self.defaultSenderCert.serializedData)
            }
        }.done {
            completed.fulfill()
        }
        self.wait(for: [completed], timeout: 1.0)
    }
    // MARK: - Util

    func buildServerCertificateProto() -> SMKProtoServerCertificate {
        let serverKey = try! Curve25519.generateKeyPair().ecPublicKey().serialized
        let certificateData = try! SMKProtoServerCertificateCertificate.builder(id: 1,
                                                                                key: serverKey).buildSerializedData()

        let signatureData = Randomness.generateRandomBytes(ECCSignatureLength)

        let wrapperProto = SMKProtoServerCertificate.builder(certificate: certificateData,
                                                             signature: signatureData)

        return try! wrapperProto.build()
    }

    func buildSenderCertificateProto(uuidOnly: Bool) -> SMKProtoSenderCertificate {
        let expires = NSDate.ows_millisecondTimeStamp() + kWeekInMs
        let identityKey = try! Curve25519.generateKeyPair().ecPublicKey().serialized
        let signer = buildServerCertificateProto()
        let certificateBuilder = SMKProtoSenderCertificateCertificate.builder(senderDevice: 1,
                                                                              expires: expires,
                                                                              identityKey: identityKey,
                                                                              signer: signer)
        if !uuidOnly { certificateBuilder.setSenderE164(aliceE164) }
        certificateBuilder.setSenderUuid(aliceUuid.uuidString)
        let certificateData = try! certificateBuilder.buildSerializedData()

        let signatureData = Randomness.generateRandomBytes(ECCSignatureLength)

        let wrapperProto = try! SMKProtoSenderCertificate.builder(certificate: certificateData,
                                                                  signature: signatureData).build()

        return wrapperProto
    }
}

// MARK: -

class MockCertificateValidator: NSObject, SMKCertificateValidator {
    @objc public func throwswrapped_validate(senderCertificate: SMKSenderCertificate, validationTime: UInt64) throws {
        // Do not throw
    }

    @objc public func throwswrapped_validate(serverCertificate: SMKServerCertificate) throws {
        // Do not throw
    }
}
