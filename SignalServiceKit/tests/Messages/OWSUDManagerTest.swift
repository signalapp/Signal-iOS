//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Foundation
import Curve25519Kit
import SignalCoreKit
import LibSignalClient
@testable import SignalServiceKit

class OWSUDManagerTest: SSKBaseTestSwift {

    private var udManagerImpl: OWSUDManagerImpl {
        return SSKEnvironment.shared.udManager as! OWSUDManagerImpl
    }

    // MARK: - Setup/Teardown

    let aliceE164 = "+13213214321"
    let aliceAci = Aci.randomForTesting()
    let trustRoot = IdentityKeyPair.generate()
    lazy var aliceAddress = SignalServiceAddress(serviceId: aliceAci, phoneNumber: aliceE164)
    lazy var defaultSenderCert = buildSenderCertificate(uuidOnly: false)
    lazy var uuidOnlySenderCert = buildSenderCertificate(uuidOnly: true)

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(localIdentifiers: LocalIdentifiers(aci: aliceAci, pni: nil, phoneNumber: aliceE164))

        // Configure UDManager
        self.write { transaction in
            self.profileManager.setProfileKeyData(
                OWSAES256Key.generateRandom().keyData,
                for: self.aliceAddress,
                userProfileWriter: .tests,
                authedAccount: .implicit(),
                transaction: transaction
            )
        }

        udManagerImpl.trustRoot = ECPublicKey(trustRoot.publicKey)
        udManagerImpl.setSenderCertificate(uuidOnly: true, certificateData: Data(uuidOnlySenderCert.serialize()))
        udManagerImpl.setSenderCertificate(uuidOnly: false, certificateData: Data(defaultSenderCert.serialize()))
    }

    // MARK: - Tests

    func testMode_noProfileKey() {
        XCTAssert(udManagerImpl.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)

        // Ensure UD is enabled by setting our own access level to enabled.
        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: aliceAci, tx: tx)
        }

        let bobRecipientAci = Aci.randomForTesting()

        write { tx in
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.unknown, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssert(udAccess.isRandomKey)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.disabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)
            XCTAssertNil(udAccess)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)
            XCTAssertNil(udAccess)
        }

        write { tx in
            // Bob should work in unrestricted mode, even if he doesn't have a profile key.
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
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
        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: aliceAci, tx: tx)
        }

        let bobRecipientAci = Aci.randomForTesting()
        self.write { transaction in
            self.profileManager.setProfileKeyData(
                OWSAES256Key.generateRandom().keyData,
                for: SignalServiceAddress(bobRecipientAci),
                userProfileWriter: .tests,
                authedAccount: .implicit(),
                transaction: transaction
            )
        }

        write { tx in
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.unknown, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)

        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.disabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)
            XCTAssertNil(udAccess)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.enabled, udAccess.udAccessMode)
            XCTAssertFalse(udAccess.isRandomKey)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
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
        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: aliceAci, tx: tx)
        }

        let bobRecipientAci = Aci.randomForTesting()
        write { transaction in
            self.profileManager.setProfileKeyData(
                OWSAES256Key.generateRandom().keyData,
                for: SignalServiceAddress(bobRecipientAci),
                userProfileWriter: .tests,
                authedAccount: .implicit(),
                transaction: transaction
            )
        }

        let senderCertificates = SenderCertificates(
            defaultCert: defaultSenderCert,
            uuidOnlyCert: uuidOnlySenderCert
        )

        read { tx in
            let sendingAccess = self.udManagerImpl.udSendingAccess(
                for: bobRecipientAci,
                phoneNumberSharingMode: .everybody,
                senderCertificates: senderCertificates,
                tx: tx
            )!
            XCTAssertEqual(.unknown, sendingAccess.udAccess.udAccessMode)
            XCTAssertFalse(sendingAccess.udAccess.isRandomKey)
            XCTAssertEqual(sendingAccess.senderCertificate.serialize(), defaultSenderCert.serialize())
        }

        read { tx in
            let sendingAccess = self.udManagerImpl.udSendingAccess(
                for: bobRecipientAci,
                phoneNumberSharingMode: .nobody,
                senderCertificates: senderCertificates,
                tx: tx
            )!
            XCTAssertEqual(.unknown, sendingAccess.udAccess.udAccessMode)
            XCTAssertFalse(sendingAccess.udAccess.isRandomKey)
            XCTAssertEqual(sendingAccess.senderCertificate.serialize(), self.uuidOnlySenderCert.serialize())
        }
    }

    func test_certificateChoiceWithPhoneNumberShared() {
        XCTAssert(udManagerImpl.hasSenderCertificates())

        XCTAssert(tsAccountManager.isRegistered)
        guard let localAddress = tsAccountManager.localAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        let identityManager = DependenciesBridge.shared.identityManager

        // Ensure UD is enabled by setting our own access level to enabled.
        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: aliceAci, tx: tx)
        }

        let bobAci = Aci.randomForTesting()
        write { transaction in
            self.profileManager.setProfileKeyData(
                OWSAES256Key.generateRandom().keyData,
                for: SignalServiceAddress(bobAci),
                userProfileWriter: .tests,
                authedAccount: .implicit(),
                transaction: transaction
            )
            identityManager.setShouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write)
        }

        let senderCertificates = SenderCertificates(
            defaultCert: defaultSenderCert,
            uuidOnlyCert: uuidOnlySenderCert
        )

        read { tx in
            let sendingAccess = udManagerImpl.udSendingAccess(
                for: bobAci,
                phoneNumberSharingMode: .everybody,
                senderCertificates: senderCertificates,
                tx: tx
            )!
            XCTAssertEqual(sendingAccess.senderCertificate.serialize(), defaultSenderCert.serialize())
        }

        read { tx in
            let sendingAccess = udManagerImpl.udSendingAccess(
                for: bobAci,
                phoneNumberSharingMode: .nobody,
                senderCertificates: senderCertificates,
                tx: tx
            )!
            XCTAssertEqual(sendingAccess.senderCertificate.serialize(), defaultSenderCert.serialize())
        }

        // Make sure it resets on clear.
        write { transaction in
            self.profileManager.setProfileKeyData(
                OWSAES256Key.generateRandom().keyData,
                for: SignalServiceAddress(bobAci),
                userProfileWriter: .tests,
                authedAccount: .implicit(),
                transaction: transaction
            )
            identityManager.clearShouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write)
        }

        read { tx in
            let sendingAccess = udManagerImpl.udSendingAccess(
                for: bobAci,
                phoneNumberSharingMode: .nobody,
                senderCertificates: senderCertificates,
                tx: tx
            )!
            XCTAssertEqual(sendingAccess.senderCertificate.serialize(), uuidOnlySenderCert.serialize())
        }
    }

    // MARK: - Util

    func buildSenderCertificate(uuidOnly: Bool) -> SenderCertificate {
        let serverKeys = IdentityKeyPair.generate()
        let serverCert = try! ServerCertificate(keyId: 1,
                                                publicKey: serverKeys.publicKey,
                                                trustRoot: trustRoot.privateKey)

        var senderAddress = try! SealedSenderAddress(e164: nil, aci: aliceAci, deviceId: 1)
        if !uuidOnly {
            senderAddress.e164 = aliceE164
        }

        let expires = NSDate.ows_millisecondTimeStamp() + kWeekInMs
        let senderKeys = IdentityKeyPair.generate()
        return try! SenderCertificate(sender: senderAddress,
                                      publicKey: senderKeys.publicKey,
                                      expiration: expires,
                                      signerCertificate: serverCert,
                                      signerKey: serverKeys.privateKey)
    }
}
