//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import LibSignalClient
import XCTest

@testable import SignalMessaging
@testable import SignalServiceKit

class ContactStreamTest: SignalBaseTest {

    // MARK: - Test Life Cycle

    override func setUp() {
        super.setUp()
        Self.databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
    }

    // MARK: -

    let outputContactSyncData = "GQoMKzEzMjMxMTExMTExEgdBbGljZS0xQAAxEgdBbGljZS0yQABKJDMxY2UxNDEyLTlhMjgtNGU2Zi1iNGVlLTIyMjIyMjIyMjIyMj8KDCsxMzIxMzMzMzMzMxIHQWxpY2UtM0AASiQxZDRhYjA0NS04OGZiLTRjNGUtOWY2YS0zMzMzMzMzMzMzMzM="

    func test_writeContactSync() throws {
        let signalAccounts = [
            SignalAccount(address: SignalServiceAddress(phoneNumber: "+13231111111")),
            SignalAccount(address: SignalServiceAddress(aciString: "31ce1412-9a28-4e6f-b4ee-222222222222")),
            SignalAccount(address: SignalServiceAddress(aciString: "1d4ab045-88fb-4c4e-9f6a-333333333333", phoneNumber: "+13213333333"))
        ]

        let streamData = try buildContactSyncData(signalAccounts: signalAccounts)

        XCTAssertEqual(streamData.base64EncodedString(), outputContactSyncData)
    }

    func test_readContactSync() throws {
        var contacts: [ContactDetails] = []

        let data = Data(base64Encoded: outputContactSyncData)!
        try data.withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let contactStream = ContactsInputStream(inputStream: inputStream)
                while let nextContact = try contactStream.decodeContact() {
                    contacts.append(nextContact)
                }
            }
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

    func buildContactSyncData(signalAccounts: [SignalAccount]) throws -> Data {
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        defer { dataOutputStream.close() }
        let contactOutputStream = ContactOutputStream(outputStream: dataOutputStream)

        for signalAccount in signalAccounts {
            let contactFactory = ContactFactory()
            contactFactory.fullNameBuilder = {
                "Alice-\(signalAccount.recipientAddress.serviceIdentifier!.suffix(1))"
            }
            contactFactory.cnContactIdBuilder = { "123" }
            contactFactory.uniqueIdBuilder = { "123" }

            signalAccount.replaceContactForTests(try contactFactory.build())

            try contactOutputStream.writeContact(
                aci: signalAccount.recipientServiceId as? Aci,
                phoneNumber: E164(signalAccount.recipientPhoneNumber),
                signalAccount: signalAccount,
                disappearingMessagesConfiguration: nil,
                inboxPosition: nil,
                isBlocked: false
            )
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }
}
