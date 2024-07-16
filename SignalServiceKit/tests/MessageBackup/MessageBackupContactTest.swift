//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupContactTest: MessageBackupIntegrationTestCase {
    private let aciFixture = Aci.constantForTesting("4076995E-0531-4042-A9E4-1E67A77DF358")
    private let pniFixture = Pni.constantForTesting("PNI:26FC02A2-BA58-4A7D-B081-9DA23971570A")

    private func assert(
        recipient: SignalRecipient,
        username: String = "han_solo.44",
        phoneNumber: String = "+17735550199",
        isBlocked: Bool,
        isHidden: Bool,
        isRegistered: Bool,
        unregisteredAtTimestamp: UInt64?,
        isWhitelisted: Bool,
        givenName: String = "Han",
        familyName: String = "Solo",
        isStoryHidden: Bool = true,
        sdsTx: SDSAnyReadTransaction,
        tx: DBReadTransaction
    ) {
        XCTAssertEqual(recipient.aci, aciFixture)
        XCTAssertEqual(recipient.pni, pniFixture)
        XCTAssertEqual(deps.usernameLookupManager.fetchUsername(forAci: recipient.aci!, transaction: tx), username)
        XCTAssertEqual(recipient.phoneNumber?.stringValue, phoneNumber)
        XCTAssertEqual(blockingManager.isAddressBlocked(recipient.address, transaction: sdsTx), isBlocked)
        XCTAssertEqual(deps.recipientHidingManager.isHiddenRecipient(recipient, tx: tx), isHidden)
        XCTAssertEqual(recipient.isRegistered, isRegistered)
        XCTAssertEqual(recipient.unregisteredAtTimestamp, unregisteredAtTimestamp)
        let recipientProfile = profileManager.getUserProfile(for: recipient.address, transaction: sdsTx)
        XCTAssertNotNil(recipientProfile?.profileKey)
        XCTAssertEqual(profileManager.isUser(inProfileWhitelist: recipient.address, transaction: sdsTx), isWhitelisted)
        XCTAssertEqual(recipientProfile?.givenName, givenName)
        XCTAssertEqual(recipientProfile?.familyName, familyName)
        XCTAssertEqual(StoryStoreImpl().getOrCreateStoryContextAssociatedData(for: recipient.aci!, tx: tx).isHidden, isStoryHidden)
    }

    private func allRecipients(tx: any DBReadTransaction) -> [SignalRecipient] {
        var result = [SignalRecipient]()
        deps.recipientDatabaseTable.enumerateAll(tx: tx) { result.append($0) }
        return result
    }

    func testRegisteredBlockedContact() async throws {
        try await runTest(backupName: "registered-blocked-contact") { sdsTx, tx in
            let allRecipients = allRecipients(tx: tx)
            XCTAssertEqual(allRecipients.count, 1)

            assert(
                recipient: allRecipients.first!,
                isBlocked: true,
                isHidden: true,
                isRegistered: true,
                unregisteredAtTimestamp: nil,
                isWhitelisted: false,
                sdsTx: sdsTx,
                tx: tx
            )
        }
    }

    func testUnregisteredContact() async throws {
        try await runTest(backupName: "unregistered-contact") { sdsTx, tx in
            let allRecipients = allRecipients(tx: tx)
            XCTAssertEqual(allRecipients.count, 1)

            assert(
                recipient: allRecipients.first!,
                isBlocked: false,
                isHidden: false,
                isRegistered: false,
                unregisteredAtTimestamp: 1713157772000,
                isWhitelisted: true,
                sdsTx: sdsTx,
                tx: tx
            )
        }
    }
}
