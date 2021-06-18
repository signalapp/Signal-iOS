//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import Curve25519Kit
import SignalCoreKit
import SignalMetadataKit
import SignalClient
@testable import SignalServiceKit

class OWSUDManagerTest: SSKBaseTestSwift {

    private var udManagerImpl: OWSUDManagerImpl {
        return SSKEnvironment.shared.udManager as! OWSUDManagerImpl
    }

    // MARK: - Setup/Teardown

    let aliceE164 = "+13213214321"
    let aliceUuid = UUID()
    lazy var aliceAddress = SignalServiceAddress(uuid: aliceUuid, phoneNumber: aliceE164)
    lazy var defaultSenderCert = try! SenderCertificate(buildSenderCertificateProto(uuidOnly: false).serializedData())
    lazy var uuidOnlySenderCert = try! SenderCertificate(buildSenderCertificateProto(uuidOnly: true).serializedData())

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: aliceE164, uuid: aliceUuid)

        // Configure UDManager
        self.write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData,
                                                  for: self.aliceAddress,
                                                  userProfileWriter: .tests,
                                                  transaction: transaction)
        }

        udManagerImpl.certificateValidator = MockCertificateValidator()
        udManagerImpl.setSenderCertificate(uuidOnly: true, certificateData: Data(uuidOnlySenderCert.serialize()))
        udManagerImpl.setSenderCertificate(uuidOnly: false, certificateData: Data(defaultSenderCert.serialize()))
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // MARK: - Tests

    func testMode_self() {
        XCTAssert(udManagerImpl.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        do {
            let udAccess = udManagerImpl.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.unknown, address: aliceAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.disabled, address: aliceAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: localAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.enabled, address: aliceAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, address: aliceAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: localAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unrestricted, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }
    }

    func testMode_noProfileKey() {
        XCTAssert(udManagerImpl.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManagerImpl.setUnidentifiedAccessMode(.enabled, address: localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        self.read { transaction in
            XCTAssertNil(self.profileManager.profileKeyData(for: bobRecipientAddress, transaction: transaction))
        }

        do {
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.unknown, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.disabled, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.enabled, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            // Bob should work in unrestricted mode, even if he doesn't have a profile key.
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unrestricted, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }
    }

    func testMode_withProfileKey() {
        XCTAssert(udManagerImpl.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManagerImpl.setUnidentifiedAccessMode(.enabled, address: localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        self.write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData,
                                                  for: bobRecipientAddress,
                                                  userProfileWriter: .tests,
                                                  transaction: transaction)
        }

        do {
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.unknown, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)

        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.disabled, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)
            XCTAssertNil(udAccess)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.enabled, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        do {
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, address: bobRecipientAddress)
            let udAccess = udManagerImpl.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
            XCTAssertNotNil(udAccess)
            XCTAssertEqual(.unrestricted, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }
    }

    func test_senderAccess() {
        XCTAssert(udManagerImpl.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManagerImpl.setUnidentifiedAccessMode(.enabled, address: localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData,
                                                  for: bobRecipientAddress,
                                                  userProfileWriter: .tests,
                                                  transaction: transaction)
        }

        let completed = self.expectation(description: "completed")
        udManagerImpl.ensureSenderCertificates(certificateExpirationPolicy: .strict).done { senderCertificates in
            do {
                let sendingAccess = self.udManagerImpl.udSendingAccess(forAddress: bobRecipientAddress, requireSyncAccess: false, senderCertificates: senderCertificates)!
                XCTAssertEqual(.unknown, sendingAccess.udAccess.udAccessMode)
                XCTAssertFalse(sendingAccess.udAccess.isRandomKey)
                XCTAssertEqual(sendingAccess.senderCertificate.serialize(),
                               self.defaultSenderCert.serialize())
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
    public func throwswrapped_validate(senderCertificate: SenderCertificate, validationTime: UInt64) throws {
        // Do not throw
    }

    public func throwswrapped_validate(serverCertificate: ServerCertificate) throws {
        // Do not throw
    }
}
