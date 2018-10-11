//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import SignalCoreKit
import SignalMetadataKit
@testable import SignalServiceKit

class MockCertificateValidator: NSObject, SMKCertificateValidator {

    @objc public func validate(senderCertificate: SMKSenderCertificate, validationTime: UInt64) throws {
        // Do not throw
    }

    @objc public func validate(serverCertificate: SMKServerCertificate) throws {
        // Do not throw
    }
}

// MARK: -

class OWSUDManagerTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()

        let aliceRecipientId = "+13213214321"
        SSKEnvironment.shared.tsAccountManager.registerForTests(withLocalNumber: aliceRecipientId)

        // Configure UDManager
        let profileManager = SSKEnvironment.shared.profileManager
        profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, forRecipientId: aliceRecipientId)

        let udManager = SSKEnvironment.shared.udManager as! OWSUDManagerImpl
        udManager.certificateValidator = MockCertificateValidator()

        let serverCertificate = SMKServerCertificate(keyId: 1,
                                                     key: try! ECPublicKey(keyData: Randomness.generateRandomBytes(ECCKeyLength)),
                                                     signatureData: Randomness.generateRandomBytes(ECCSignatureLength))
        let senderCertificate = SMKSenderCertificate(signer: serverCertificate,
                                                     key: try! ECPublicKey(keyData: Randomness.generateRandomBytes(ECCKeyLength)),
                                                     senderDeviceId: 1,
                                                     senderRecipientId: aliceRecipientId,
                                                     expirationTimestamp: NSDate.ows_millisecondTimeStamp() + kWeekInMs,
                                                     signatureData: Randomness.generateRandomBytes(ECCSignatureLength))

        udManager.setSenderCertificate(try! senderCertificate.serialized())
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testMode_self() {

        let udManager = SSKEnvironment.shared.udManager as! OWSUDManagerImpl

        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(SSKEnvironment.shared.tsAccountManager.isRegistered())
        XCTAssertNotNil(SSKEnvironment.shared.tsAccountManager.localNumber())
        XCTAssert(SSKEnvironment.shared.tsAccountManager.localNumber()!.count > 0)

        let aliceRecipientId = "+13213214321"

        // Self should be enabled regardless of what we "set" our mode to.
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(recipientId: aliceRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: aliceRecipientId))

        udManager.setUnidentifiedAccessMode(.unknown, recipientId: aliceRecipientId)
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(recipientId: aliceRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: aliceRecipientId))

        udManager.setUnidentifiedAccessMode(.disabled, recipientId: aliceRecipientId)
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(recipientId: aliceRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: aliceRecipientId))

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: aliceRecipientId)
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(recipientId: aliceRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: aliceRecipientId))

        udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: aliceRecipientId)
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(recipientId: aliceRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: aliceRecipientId))
    }

    func testMode_noProfileKey() {

        let udManager = SSKEnvironment.shared.udManager as! OWSUDManagerImpl

        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(SSKEnvironment.shared.tsAccountManager.isRegistered())
        XCTAssertNotNil(SSKEnvironment.shared.tsAccountManager.localNumber())
        XCTAssert(SSKEnvironment.shared.tsAccountManager.localNumber()!.count > 0)

        let bobRecipientId = "+13213214322"

        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.unknown, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.disabled, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.disabled, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.enabled, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        // Bob should work in unrestricted mode, even if he doesn't have a profile key.
        udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.unrestricted, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: bobRecipientId))
    }

    func testMode_withProfileKey() {

        let udManager = SSKEnvironment.shared.udManager as! OWSUDManagerImpl

        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(SSKEnvironment.shared.tsAccountManager.isRegistered())
        XCTAssertNotNil(SSKEnvironment.shared.tsAccountManager.localNumber())
        XCTAssert(SSKEnvironment.shared.tsAccountManager.localNumber()!.count > 0)

        let bobRecipientId = "+13213214322"
        let profileManager = SSKEnvironment.shared.profileManager
        profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, forRecipientId: bobRecipientId)

        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.unknown, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.disabled, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.disabled, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.enabled, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: bobRecipientId))

        udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.unrestricted, udManager.unidentifiedAccessMode(recipientId: bobRecipientId))
        XCTAssertNotNil(udManager.getAccess(forRecipientId: bobRecipientId))
    }
}
