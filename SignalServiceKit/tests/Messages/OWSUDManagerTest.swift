//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
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

    // MARK: - Singletons

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var udManager: OWSUDManagerImpl {
        return SSKEnvironment.shared.udManager as! OWSUDManagerImpl
    }

    private var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    // MARK: registration
    let aliceRecipientId = "+13213214321"

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: aliceRecipientId)

        // Configure UDManager
        profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, forRecipientId: aliceRecipientId)

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

        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(tsAccountManager.isRegistered)
        XCTAssertNotNil(tsAccountManager.localNumber())
        XCTAssert(tsAccountManager.localNumber()!.count > 0)

        var udAccess: OWSUDAccess!

        XCTAssertEqual(.enabled, udManager.unidentifiedAccessMode(forRecipientId: aliceRecipientId))
        udAccess = udManager.udAccess(forRecipientId: aliceRecipientId, requireSyncAccess: false)
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unknown, recipientId: aliceRecipientId)
        XCTAssertEqual(.unknown, udManager.unidentifiedAccessMode(forRecipientId: aliceRecipientId))
        udAccess = udManager.udAccess(forRecipientId: aliceRecipientId, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.disabled, recipientId: aliceRecipientId)
        XCTAssertEqual(.disabled, udManager.unidentifiedAccessMode(forRecipientId: aliceRecipientId))
        XCTAssertNil(udManager.udAccess(forRecipientId: aliceRecipientId, requireSyncAccess: false))

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: aliceRecipientId)
        XCTAssert(UnidentifiedAccessMode.enabled == udManager.unidentifiedAccessMode(forRecipientId: aliceRecipientId))
        udAccess = udManager.udAccess(forRecipientId: aliceRecipientId, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: aliceRecipientId)
        XCTAssertEqual(.unrestricted, udManager.unidentifiedAccessMode(forRecipientId: aliceRecipientId))
        udAccess = udManager.udAccess(forRecipientId: aliceRecipientId, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)
    }

    func testMode_noProfileKey() {

        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(tsAccountManager.isRegistered)
        XCTAssertNotNil(tsAccountManager.localNumber())
        XCTAssert(tsAccountManager.localNumber()!.count > 0)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, recipientId: tsAccountManager.localNumber()!)

        let bobRecipientId = "+13213214322"
        XCTAssertNotEqual(bobRecipientId, tsAccountManager.localNumber()!)

        var udAccess: OWSUDAccess!

        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unknown, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.unknown, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.disabled, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.disabled, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        XCTAssertNil(udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false))

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.enabled, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        XCTAssertNil(udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false))

        // Bob should work in unrestricted mode, even if he doesn't have a profile key.
        udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: bobRecipientId)
        XCTAssertEqual(UnidentifiedAccessMode.unrestricted, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)
    }

    func testMode_withProfileKey() {
        XCTAssert(udManager.hasSenderCertificate())
        XCTAssert(tsAccountManager.isRegistered)
        XCTAssertNotNil(tsAccountManager.localNumber())
        XCTAssert(tsAccountManager.localNumber()!.count > 0)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, recipientId: tsAccountManager.localNumber()!)

        let bobRecipientId = "+13213214322"
        XCTAssertNotEqual(bobRecipientId, tsAccountManager.localNumber()!)
        profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, forRecipientId: bobRecipientId)

        var udAccess: OWSUDAccess!

        XCTAssertEqual(.unknown, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unknown, recipientId: bobRecipientId)
        XCTAssertEqual(.unknown, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.disabled, recipientId: bobRecipientId)
        XCTAssertEqual(.disabled, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        XCTAssertNil(udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false))

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: bobRecipientId)
        XCTAssertEqual(.enabled, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssertFalse(udAccess.isRandomKey)

        udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: bobRecipientId)
        XCTAssertEqual(.unrestricted, udManager.unidentifiedAccessMode(forRecipientId: bobRecipientId))
        udAccess = udManager.udAccess(forRecipientId: bobRecipientId, requireSyncAccess: false)!
        XCTAssert(udAccess.isRandomKey)
    }
}
