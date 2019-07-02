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
    let aliceUUID = UUID()
    lazy var aliceAddress = SignalServiceAddress(uuid: aliceUUID, phoneNumber: aliceRecipientId)

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: aliceRecipientId, uuid: aliceUUID)

        // Configure UDManager
        profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, for: aliceAddress)

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
        XCTAssertNotNil(tsAccountManager.localAddress.isValid)
        XCTAssert(tsAccountManager.localNumber()!.count > 0)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, address: tsAccountManager.localAddress)

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
        XCTAssertNotNil(tsAccountManager.localNumber())
        XCTAssert(tsAccountManager.localNumber()!.count > 0)

        // Ensure UD is enabled by setting our own access level to enabled.
        udManager.setUnidentifiedAccessMode(.enabled, address: tsAccountManager.localAddress)

        let bobRecipientAddress = SignalServiceAddress(phoneNumber: "+13213214322")
        XCTAssertFalse(bobRecipientAddress.isLocalAddress)
        profileManager.setProfileKeyData(OWSAES256Key.generateRandom().keyData, for: bobRecipientAddress)

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
}
