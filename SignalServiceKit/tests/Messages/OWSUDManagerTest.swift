//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import Curve25519Kit
import SignalCoreKit
import SignalMetadataKit
@testable import SignalServiceKit

class MockCertificateValidator: NSObject, SMKCertificateValidator {
    @objc public func throwswrapped_validate(senderCertificate: SMKSenderCertificate, validationTime: UInt64) throws {
        // Do not throw
    }

    @objc public func throwswrapped_validate(serverCertificate: SMKServerCertificate) throws {
        // Do not throw
    }
}

// MARK: -

class OWSUDManagerTest: SSKBaseTestSwift {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var udManager: OWSUDManagerImpl {
        return SSKEnvironment.shared.udManager as! OWSUDManagerImpl
    }

    private var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    // MARK: - Setup/Teardown

    let aliceE164 = "+13213214321"
    let aliceUuid = UUID()
    lazy var aliceAddress = SignalServiceAddress(uuid: aliceUuid, phoneNumber: aliceE164)

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: aliceE164, uuid: aliceUuid)

        // Configure UDManager
        self.write { transaction in
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, for: self.aliceAddress, transaction: transaction)
        }

        udManager.certificateValidator = MockCertificateValidator()

        let senderCertificate = try! SMKSenderCertificate(serializedData: buildSenderCertificateProto().serializedData())
        udManager.setSenderCertificate(senderCertificate.serializedData)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // MARK: - Tests

    func testMode_self() {

        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        var udAccess: OWSUDAccess!

        XCTAssertEqual(.enabled, udManager.unidentifiedAccessMode(forAddress: aliceAddress))
        udAccess = udManager.udAccess(forAddress: aliceAddress, requireSyncAccess: false)
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unknown, address: aliceAddress)
        XCTAssertEqual(.unknown, udManager.unidentifiedAccessMode(forAddress: aliceAddress))
        udAccess = udManager.udAccess(forAddress: aliceAddress, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.disabled, address: aliceAddress)
        XCTAssertEqual(.disabled, udManager.unidentifiedAccessMode(forAddress: aliceAddress))
        XCTAssertNil(udManager.udAccess(forAddress: aliceAddress, requireSyncAccess: false))

        udManager.setUnidentifiedAccessMode(.enabled, address: aliceAddress)
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(forAddress: aliceAddress))
        udAccess = udManager.udAccess(forAddress: aliceAddress, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unrestricted, address: aliceAddress)
        XCTAssertEqual(.unrestricted, udManager.unidentifiedAccessMode(forAddress: aliceAddress))
        udAccess = udManager.udAccess(forAddress: aliceAddress, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)
    }

    func testMode_noProfileKey() {

        XCTAssert(udManager.hasSenderCertificate())
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

        var udAccess: OWSUDAccess!

        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unknown, address: bobRecipientAddress)
        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.disabled, address: bobRecipientAddress)
        XCTAssertEqual(UnidentifiedAccessMode.disabled, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        XCTAssertNil(udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false))

        udManager.setUnidentifiedAccessMode(.enabled, address: bobRecipientAddress)
        XCTAssertEqual(UnidentifiedAccessMode.enabled, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        XCTAssertNil(udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false))

        // Bob should work in unrestricted mode, even if he doesn't have a profile key.
        udManager.setUnidentifiedAccessMode(.unrestricted, address: bobRecipientAddress)
        XCTAssertEqual(UnidentifiedAccessMode.unrestricted, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)
    }

    func testMode_withProfileKey() {
        XCTAssert(udManager.hasSenderCertificate())
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
            self.profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, for: bobRecipientAddress, transaction: transaction)
        }

        var udAccess: OWSUDAccess!

        XCTAssertEqual(.unknown, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unknown, address: bobRecipientAddress)
        XCTAssertEqual(.unknown, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.disabled, address: bobRecipientAddress)
        XCTAssertEqual(.disabled, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        XCTAssertNil(udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false))

        udManager.setUnidentifiedAccessMode(.enabled, address: bobRecipientAddress)
        XCTAssertEqual(.enabled, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unrestricted, address: bobRecipientAddress)
        XCTAssertEqual(.unrestricted, udManager.unidentifiedAccessMode(forAddress: bobRecipientAddress))
        udAccess = udManager.udAccess(forAddress: bobRecipientAddress, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)
    }

    // MARK: - Util

    func buildServerCertificateProto() -> SMKProtoServerCertificate {
        let serverKey = try! Curve25519.generateKeyPair().ecPublicKey().serialized
        let certificateData = try! SMKProtoServerCertificateCertificate.builder(id: 1,
                                                                                key: serverKey ).buildSerializedData()

        let signatureData = Randomness.generateRandomBytes(ECCSignatureLength)

        let wrapperProto = SMKProtoServerCertificate.builder(certificate: certificateData,
                                                             signature: signatureData)

        return try! wrapperProto.build()
    }

    func buildSenderCertificateProto() -> SMKProtoSenderCertificate {
        let expires = NSDate.ows_millisecondTimeStamp() + kWeekInMs
        let identityKey = try! Curve25519.generateKeyPair().ecPublicKey().serialized
        let signer = buildServerCertificateProto()
        let certificateBuilder = SMKProtoSenderCertificateCertificate.builder(senderDevice: 1,
                                                                              expires: expires,
                                                                              identityKey: identityKey,
                                                                              signer: signer)
        certificateBuilder.setSenderE164(aliceE164)
        certificateBuilder.setSenderUuid(aliceUuid.uuidString)
        let certificateData = try! certificateBuilder.buildSerializedData()

        let signatureData = Randomness.generateRandomBytes(ECCSignatureLength)

        let wrapperProto = try! SMKProtoSenderCertificate.builder(certificate: certificateData,
                                                                  signature: signatureData).build()

        return wrapperProto
    }
}
