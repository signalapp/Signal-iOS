//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalServiceKit

class ContactShareViewHelperTests: SignalBaseTest {
    private let contactShareViewHelper = ContactShareViewHelper()

    private var aciContactShareNameManager: any AciContactShareNameManager {
        DependenciesBridge.shared.aciContactShareNameManager
    }

    private func makeRecipient(_ aci: Aci) -> SignalRecipient {
        return write { tx in
            DependenciesBridge.shared.recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        }
    }

    func testRecordsSharedName() {
        let aci = Aci.randomForTesting()
        let recipient = makeRecipient(aci)

        write { tx in
            contactShareViewHelper.recordContactShareNameIfNecessary(
                OWSContactName(givenName: "Bob", familyName: "Bobson"),
                forAci: aci,
                tx: tx,
            )
        }

        let name = read { tx in aciContactShareNameManager.fetchName(recipient: recipient, tx: tx) }
        XCTAssertEqual(name?.givenName, "Bob")
        XCTAssertEqual(name?.familyName, "Bobson")
    }

    func testRecordsNicknameWithoutPersonName() {
        let aci = Aci.randomForTesting()
        let recipient = makeRecipient(aci)

        write { tx in
            contactShareViewHelper.recordContactShareNameIfNecessary(
                OWSContactName(nickname: "Bobby", organizationName: "Acme"),
                forAci: aci,
                tx: tx,
            )
        }

        let name = read { tx in aciContactShareNameManager.fetchName(recipient: recipient, tx: tx) }
        XCTAssertEqual(name?.givenName, "Bobby")
        XCTAssertNil(name?.familyName)
    }

    func testRecordsOrganizationNameWithoutPersonName() {
        let aci = Aci.randomForTesting()
        let recipient = makeRecipient(aci)

        write { tx in
            contactShareViewHelper.recordContactShareNameIfNecessary(
                OWSContactName(givenName: " ", organizationName: "Acme"),
                forAci: aci,
                tx: tx,
            )
        }

        let name = read { tx in aciContactShareNameManager.fetchName(recipient: recipient, tx: tx) }
        XCTAssertEqual(name?.givenName, "Acme")
        XCTAssertNil(name?.familyName)
    }

    func testReadFirstVariantRecordsSharedName() {
        let aci = Aci.randomForTesting()
        let recipient = makeRecipient(aci)

        contactShareViewHelper.recordContactShareNameIfNecessary(OWSContactName(givenName: "Bob"), forAci: aci)

        let name = read { tx in aciContactShareNameManager.fetchName(recipient: recipient, tx: tx) }
        XCTAssertEqual(name?.givenName, "Bob")
    }

    func testDoesNotOverwriteRecordedName() {
        let aci = Aci.randomForTesting()
        let recipient = makeRecipient(aci)

        contactShareViewHelper.recordContactShareNameIfNecessary(OWSContactName(givenName: "Bob"), forAci: aci)
        contactShareViewHelper.recordContactShareNameIfNecessary(OWSContactName(givenName: "Robert"), forAci: aci)

        let name = read { tx in aciContactShareNameManager.fetchName(recipient: recipient, tx: tx) }
        XCTAssertEqual(name?.givenName, "Bob")
    }
}
