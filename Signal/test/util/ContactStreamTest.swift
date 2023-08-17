//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Contacts

@testable import SignalServiceKit

class ContactStreamTest: SignalBaseTest {

    // MARK: - Test Life Cycle

    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(localIdentifiers: .forUnitTests)
    }

    // MARK: -

    let outputContactSyncData = "GwoMKzEzMjMxMTExMTExEgdBbGljZS0xQABYADMSB0FsaWNlLTJAAEokMzFjZTE0MTItOWEyOC00ZTZmLWI0ZWUtMjIyMjIyMjIyMjIyWABBCgwrMTMyMTMzMzMzMzMSB0FsaWNlLTNAAEokMWQ0YWIwNDUtODhmYi00YzRlLTlmNmEtMzMzMzMzMzMzMzMzWAA="

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
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[1]
            XCTAssertNil(contact.phoneNumber)
            XCTAssertEqual("31CE1412-9A28-4E6F-B4EE-222222222222", contact.aci?.serviceIdUppercaseString)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[2]
            XCTAssertEqual("+13213333333", contact.phoneNumber?.stringValue)
            XCTAssertEqual("1D4AB045-88FB-4C4E-9F6A-333333333333", contact.aci?.serviceIdUppercaseString)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }
    }

    func buildContactSyncData(signalAccounts: [SignalAccount]) throws -> Data {
        let contactsManager = TestContactsManager()
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        let contactsOutputStream = OWSContactsOutputStream(outputStream: dataOutputStream)

        for signalAccount in signalAccounts {
            let contactFactory = ContactFactory()
            contactFactory.fullNameBuilder = {
                "Alice-\(signalAccount.recipientAddress.serviceIdentifier!.suffix(1))"
            }
            contactFactory.cnContactIdBuilder = { "123" }
            contactFactory.uniqueIdBuilder = { "123" }

            signalAccount.replaceContactForTests(try contactFactory.build())

            contactsOutputStream.write(signalAccount,
                                       recipientIdentity: nil,
                                       profileKeyData: nil,
                                       contactsManager: contactsManager,
                                       disappearingMessagesConfiguration: nil,
                                       isArchived: false,
                                       inboxPosition: nil,
                                       isBlocked: false)
        }

        dataOutputStream.close()
        guard !contactsOutputStream.hasError else {
            throw OWSAssertionError("contactsOutputStream.hasError")
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }
}

class TestContactsManager: NSObject, ContactsManagerProtocol {
    func fetchSignalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        nil
    }

    func isSystemContactWithSignalAccount(_ address: SignalServiceAddress) -> Bool {
        false
    }

    func isSystemContactWithSignalAccount(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    func hasNameInSystemContacts(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    func comparableName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: address)
    }

    func comparableName(for signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) -> String {
        signalAccount.recipientAddress.stringForDisplay
    }

    func displayName(for address: SignalServiceAddress) -> String {
        address.stringForDisplay
    }

    func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        address.stringForDisplay
    }

    func displayName(for signalAccount: SignalAccount) -> String {
        signalAccount.recipientAddress.stringForDisplay
    }

    func displayNames(forAddresses addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [String] {
        return addresses.map {
            $0.stringForDisplay
        }
    }

    func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        "Fake Name"
    }

    func displayNameWithSneakyTransaction(thread: TSThread) -> String {
        "Fake Name"
    }

    func shortDisplayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        address.stringForDisplay
    }

    func nameComponents(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> PersonNameComponents? {
        PersonNameComponents()
    }

    func signalAccounts() -> [SignalAccount] {
        []
    }

    func isSystemContactWithSneakyTransaction(phoneNumber: String) -> Bool {
        return true
    }

    func isSystemContact(phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    func isSystemContactWithSneakyTransaction(address: SignalServiceAddress) -> Bool {
        return true
    }

    func isSystemContact(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    func isSystemContact(withSignalAccount phoneNumber: String) -> Bool {
        true
    }

    func isSystemContact(withSignalAccount phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        true
    }

    func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        .orderedSame
    }

    public func sortSignalServiceAddresses(_ addresses: [SignalServiceAddress],
                                           transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        addresses
    }

    func cnContact(withId contactId: String?) -> CNContact? {
        nil
    }

    func avatarData(forCNContactId contactId: String?) -> Data? {
        nil
    }

    func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        nil
    }

    func leaseCacheSize(_ size: Int) -> ModelReadCacheSizeLease? {
        return nil
    }

    var unknownUserLabel: String = "unknown"
}
