//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ContactStreamTest: XCTestCase {

    let outputContactSyncData = "GwoMKzEzMjMxMTExMTExEgdBbGljZS0xQABgAR8SB0FsaWNlLTJAAGABahAxzhQSmihOb7TuIiIiIiIiLQoMKzEzMjEzMzMzMzMzEgdBbGljZS0zQABgAWoQHUqwRYj7TE6fajMzMzMzMw=="

    private func makeAccount(phoneNumber: String?, serviceId: String?, fullName: String) -> SignalAccount {
        return SignalAccount(
            recipientPhoneNumber: phoneNumber,
            recipientServiceId: serviceId.map({ Aci.constantForTesting($0) }),
            multipleAccountLabelText: nil,
            cnContactId: nil,
            givenName: "",
            familyName: "",
            nickname: "",
            fullName: fullName,
            contactAvatarHash: nil,
        )
    }

    func test_writeContactSync() throws {
        let signalAccounts = [
            makeAccount(phoneNumber: "+13231111111", serviceId: nil, fullName: "Alice-1"),
            makeAccount(phoneNumber: nil, serviceId: "31ce1412-9a28-4e6f-b4ee-222222222222", fullName: "Alice-2"),
            makeAccount(phoneNumber: "+13213333333", serviceId: "1d4ab045-88fb-4c4e-9f6a-333333333333", fullName: "Alice-3"),
        ]

        let streamData = try buildContactSyncData(signalAccounts: signalAccounts)

        XCTAssertEqual(streamData.base64EncodedString(), outputContactSyncData)
    }

    func test_readContactSync() throws {
        var contacts: [ContactDetails] = []

        let data = Data(base64Encoded: outputContactSyncData)!
        let inputStream = ChunkedInputStream(forReadingFrom: data)
        let contactStream = ContactsInputStream(inputStream: inputStream)
        while let nextContact = try contactStream.decodeContact() {
            contacts.append(nextContact)
        }

        guard contacts.count == 3 else {
            XCTFail("unexpected contact count: \(contacts.count)")
            return
        }

        do {
            let contact = contacts[0]
            XCTAssertEqual("+13231111111", contact.phoneNumber?.stringValue)
            XCTAssertNil(contact.aci)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[1]
            XCTAssertNil(contact.phoneNumber)
            XCTAssertEqual("31CE1412-9A28-4E6F-B4EE-222222222222", contact.aci?.serviceIdUppercaseString)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[2]
            XCTAssertEqual("+13213333333", contact.phoneNumber?.stringValue)
            XCTAssertEqual("1D4AB045-88FB-4C4E-9F6A-333333333333", contact.aci?.serviceIdUppercaseString)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.inboxSortOrder)
        }
    }

    private func buildContactSyncData(signalAccounts: [SignalAccount]) throws -> Data {
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        defer { dataOutputStream.close() }
        let contactOutputStream = ContactOutputStream(outputStream: dataOutputStream)

        for signalAccount in signalAccounts {
            try contactOutputStream.writeContact(
                aci: signalAccount.recipientServiceId as? Aci,
                phoneNumber: E164(signalAccount.recipientPhoneNumber),
                signalAccount: signalAccount,
                disappearingMessagesConfiguration: nil,
                inboxPosition: nil,
            )
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }
}
