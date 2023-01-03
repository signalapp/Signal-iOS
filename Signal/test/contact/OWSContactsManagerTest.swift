//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalMessaging
@testable import SignalServiceKit

class OWSContactsManagerTest: SignalBaseTest {
    private lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()

        // Replace the fake contacts manager with the real one just for this test.
        (MockSSKEnvironment.shared as! MockSSKEnvironment).setContactsManagerForMock(OWSContactsManager())

        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!,
                                          uuid: localAddress.uuid!)
    }

    override func tearDown() {
        super.tearDown()
        (MockSSKEnvironment.shared as! MockSSKEnvironment).setContactsManagerForMock(FakeContactsManager())
        let fakeProfileManager = (self.profileManager as! OWSFakeProfileManager)
        fakeProfileManager.fakeDisplayNames = nil
        fakeProfileManager.fakeUsernames = nil
    }

    private func createRecipientsAndAccounts(_ tuples: [(SignalServiceAddress, SignalAccount)]) {
        // Create recipients and accounts.
        write { transaction in
            for (address, _) in tuples {
                let recipient = SignalRecipient.fetchOrCreate(for: address, trustLevel: .high, transaction: transaction)
                recipient.markAsRegistered(transaction: transaction)
            }
            for (_, account) in tuples {
                account.anyInsert(transaction: transaction)
            }
        }
    }

    // MARK: - getPhoneNumber(s)

    func testGetPhoneNumberFromAddress() {
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumber(for: SignalServiceAddress(phoneNumber: "+17035559901"),
                                                        transaction: transaction)
            XCTAssertEqual(actual, "+17035559901")
        }
    }

    func testGetPhoneNumberFromProfile() {
        let address = SignalServiceAddress(uuid: UUID())
        let account = SignalAccount(contact: nil,
                                    contactAvatarHash: nil,
                                    multipleAccountLabelText: "home",
                                    recipientPhoneNumber: "+17035559901",
                                    recipientUUID: address.uuid?.uuidString)
        let contactsManager = self.contactsManager as! OWSContactsManager
        createRecipientsAndAccounts([(address, account)])
        read { transaction in
            let actual = contactsManager.phoneNumber(for: address, transaction: transaction)
            XCTAssertEqual(actual, "+17035559901")
        }
    }

    func testGetPhoneNumbersFromAddresses() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035559901"),
                         SignalServiceAddress(phoneNumber: "+17035559902"),
                         SignalServiceAddress(uuid: UUID())]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumbers(for: addresses, transaction: transaction)
            let expected = ["+17035559901", "+17035559902", nil]
            XCTAssertEqual(actual, expected)
        }
    }

    private func makeAccount(address: SignalServiceAddress,
                             phoneNumber: String?,
                             name: String? = nil) -> SignalAccount {
        let contact = name.map { name -> Contact in
            let parts = name.components(separatedBy: " ")
            return Contact(uniqueId: UUID().uuidString,
                           cnContactId: nil,
                           firstName: parts[0],
                           lastName: parts.count > 1 ? parts[1] : nil,
                           nickname: nil,
                           fullName: name,
                           userTextPhoneNumbers: [],
                           phoneNumberNameMap: [:],
                           parsedPhoneNumbers: [],
                           emails: [])
        }
        return SignalAccount(contact: contact,
                             contactAvatarHash: nil,
                             multipleAccountLabelText: "home",
                             recipientPhoneNumber: phoneNumber,
                             recipientUUID: address.uuid!.uuidString)
    }
    func testGetPhoneNumbersFromProfiles() {
        let aliceAddress = SignalServiceAddress(uuid: UUID())
        let aliceAccount = makeAccount(address: aliceAddress, phoneNumber: "+17035559901")

        let bobAddress = SignalServiceAddress(uuid: UUID())
        let bobAccount = makeAccount(address: bobAddress, phoneNumber: "+17035559902")

        let bogusAddress = SignalServiceAddress(uuid: UUID())

        createRecipientsAndAccounts([(aliceAddress, aliceAccount),
                                     (bobAddress, bobAccount)])
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumbers(for: [aliceAddress,
                                                            bogusAddress,
                                                            bobAddress],
                                                      transaction: transaction)
            let expected = [aliceAccount.recipientPhoneNumber,
                            nil,
                            bobAccount.recipientPhoneNumber]
            XCTAssertEqual(actual, expected)
        }
    }

    // MARK: - Display Names

    func testGetDisplayNamesWithCachedContactNames() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let accounts = [makeAccount(address: addresses[0], phoneNumber: nil, name: "Alice Aliceson"),
                        makeAccount(address: addresses[1], phoneNumber: nil, name: "Bob Bobson")]
        createRecipientsAndAccounts(Array(zip(addresses, accounts)))

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithProfileFullNames() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        (self.profileManager as! OWSFakeProfileManager).fakeDisplayNames = [
            addresses[0]: "Alice Aliceson",
            addresses[1]: "Bob Bobson"
        ]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson",
                            "Bob Bobson"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithPhoneNumbers() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035559900"),
                         SignalServiceAddress(phoneNumber: "+17035559901")]
        // Prevent default fake name from being used.
        (self.profileManager as! OWSFakeProfileManager).fakeDisplayNames = [:]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["+17035559900",
                            "+17035559901"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithUserNames() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let fakeProfileManager = (self.profileManager as! OWSFakeProfileManager)
        fakeProfileManager.fakeUsernames = [addresses[0]: "alice",
                                            addresses[1]: "bob"]
        // Prevent default fake name from being used.
        fakeProfileManager.fakeDisplayNames = [:]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["@alice",
                            "@bob"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesUnknown() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let fakeProfileManager = (self.profileManager as! OWSFakeProfileManager)
        // Prevent default fake name from being used.
        fakeProfileManager.fakeDisplayNames = [:]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Unknown",
                            "Unknown"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesMixed() {
        let aliceAddress = SignalServiceAddress(uuid: UUID())
        let aliceAccount = makeAccount(address: aliceAddress, phoneNumber: nil, name: "Alice Aliceson")
        createRecipientsAndAccounts([(aliceAddress, aliceAccount)])

        let bobAddress = SignalServiceAddress(uuid: UUID())
        (self.profileManager as! OWSFakeProfileManager).fakeDisplayNames = [bobAddress: "Bob Bobson"]

        let carolAddress = SignalServiceAddress(phoneNumber: "+17035559900")

        let daveAddress = SignalServiceAddress(uuid: UUID())
        let fakeProfileManager = (self.profileManager as! OWSFakeProfileManager)
        fakeProfileManager.fakeUsernames = [daveAddress: "dave"]

        let eveAddress = SignalServiceAddress(uuid: UUID())

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let addresses = [aliceAddress,
                             bobAddress,
                             carolAddress,
                             daveAddress,
                             eveAddress]
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson (home)",
                            "Bob Bobson",
                            "+17035559900",
                            "@dave",
                            "Unknown"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testSinglePartName() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let accounts = [makeAccount(address: addresses[0], phoneNumber: nil, name: "Alice"),
                        makeAccount(address: addresses[1], phoneNumber: nil, name: "Bob")]
        createRecipientsAndAccounts(Array(zip(addresses, accounts)))

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice (home)", "Bob (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    // MARK: - Cached Contact Names

    func testCachedContactNamesWithAccounts() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let accounts = [makeAccount(address: addresses[0], phoneNumber: nil, name: "Alice Aliceson"),
                        makeAccount(address: addresses[1], phoneNumber: nil, name: "Bob Bobson")]
        let contactsManager = OWSContactsManager()
        createRecipientsAndAccounts(Array(zip(addresses, accounts)))
        read { transaction in
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    private func contact(name: String, phoneNumber: String?) -> Contact {
        Contact(uniqueId: String(name.data(using: .utf8)!.hashValue),
                cnContactId: nil,
                firstName: nil,
                lastName: nil,
                nickname: nil,
                fullName: name,
                userTextPhoneNumbers: [phoneNumber].compactMap { $0 },
                phoneNumberNameMap: [:],
                parsedPhoneNumbers: [phoneNumber.map { PhoneNumber(fromE164: $0)! }].compactMap { $0 },
                emails: [])
    }

    private func saveContacts(_ contacts: [Contact]) {
        let phoneNumberStore = SDSKeyValueStore(collection: "ContactsManagerCache.phoneNumberStore")
        write { transaction in
            for contact in contacts {
                let data = try! NSKeyedArchiver.archivedData(withRootObject: contact, requiringSecureCoding: false)
                phoneNumberStore.setData(data, key: contact.parsedPhoneNumbers[0].toE164(), transaction: transaction)
            }
        }
    }

    func testCachedContactNamesWithNonSignalContacts() {
        let alicePhoneNumber = "+17035550000"
        let bobPhoneNumber = "+17035550001"
        let addresses = [SignalServiceAddress(phoneNumber: alicePhoneNumber),
                         SignalServiceAddress(phoneNumber: bobPhoneNumber)]
        saveContacts([contact(name: "Alice Aliceson", phoneNumber: alicePhoneNumber),
                      contact(name: "Bob Bobson", phoneNumber: bobPhoneNumber)])
        read { transaction in
            let contactsManager = OWSContactsManager()
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson", "Bob Bobson"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testCachedContactNameWithNonSignalContactsLackingPhoneNumbers() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let contactsManager = OWSContactsManager()
        read { transaction in
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            XCTAssertEqual(actual, [nil, nil])
        }
    }

    func testCachedContactNameMixed() {
        // Register alice with an account that has a full name.
        let aliceAddress = SignalServiceAddress(uuid: UUID())
        let aliceAccount = makeAccount(address: aliceAddress, phoneNumber: nil, name: "Alice Aliceson")
        createRecipientsAndAccounts(Array(zip([aliceAddress], [aliceAccount])))

        // Register bob as a non-Signal contact.
        let bobPhoneNumber = "+17035550001"
        let bobAddress = SignalServiceAddress(phoneNumber: bobPhoneNumber)
        saveContacts([contact(name: "Bob Bobson", phoneNumber: bobPhoneNumber)])

        // Who the heck is Chuck?
        let chuckAddress = SignalServiceAddress(uuid: UUID())

        read { transaction in
            let addresses = [aliceAddress, bobAddress, chuckAddress]
            let contactsManager = OWSContactsManager()
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson", nil]
            XCTAssertEqual(actual, expected)
        }
    }
}
