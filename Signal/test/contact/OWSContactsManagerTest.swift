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

    private let dbV2: MockDB = .init()

    private let mockUsernameLookupMananger: MockUsernameLookupManager = .init()

    override func setUp() {
        super.setUp()

        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!, uuid: localAddress.uuid!)

        // Replace the fake contacts manager with the real one just for this test.
        SSKEnvironment.shared.setContactsManagerForUnitTests(makeContactsManager())
    }

    override func tearDown() {
        mockUsernameLookupMananger.clearAllUsernames()
    }

    private func makeContactsManager() -> OWSContactsManager {
        let contactsManager = OWSContactsManager(swiftValues: OWSContactsManagerSwiftValues(
            usernameLookupManager: mockUsernameLookupMananger
        ))

        contactsManager.setUpSystemContacts()

        return contactsManager
    }

    private func createRecipients(_ serviceIds: [ServiceId]) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        write { tx in
            for serviceId in serviceIds {
                let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write)
                recipient.markAsRegisteredAndSave(tx: tx)
            }
        }
    }

    private func createAccounts(_ accounts: [SignalAccount]) {
        write { transaction in
            for account in accounts {
                account.anyInsert(transaction: transaction)
            }
        }
    }

    private func createContacts(_ contacts: [Contact]) {
        write { transaction in
            (self.contactsManager as! OWSContactsManager).setContactsMaps(
                .build(contacts: contacts, localNumber: localAddress.phoneNumber),
                localNumber: localAddress.phoneNumber,
                transaction: transaction
            )
        }
    }

    private func makeAccount(
        address: SignalServiceAddress,
        phoneNumber: String?,
        name: String? = nil
    ) -> SignalAccount {
        let contact = name.map { name -> Contact in
            makeContact(address: SignalServiceAddress(uuid: address.uuid!, phoneNumber: phoneNumber), name: name)
        }
        return SignalAccount(
            contact: contact,
            contactAvatarHash: nil,
            multipleAccountLabelText: "home",
            recipientPhoneNumber: phoneNumber,
            recipientUUID: address.uuid!.uuidString
        )
    }

    private func makeContact(address: SignalServiceAddress, name: String) -> Contact {
        let parts = name.components(separatedBy: " ")
        return Contact(
            address: address,
            phoneNumberLabel: "home",
            givenName: parts.first,
            familyName: parts.dropFirst().first,
            nickname: nil,
            fullName: name
        )
    }

    // MARK: - getPhoneNumber(s)

    func testGetPhoneNumberFromAddress() {
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumber(
                for: SignalServiceAddress(phoneNumber: "+17035559901"),
                transaction: transaction
            )
            XCTAssertEqual(actual, "+17035559901")
        }
    }

    func testGetPhoneNumberFromProfile() {
        let address = SignalServiceAddress(uuid: UUID())
        let account = SignalAccount(
            contact: nil,
            contactAvatarHash: nil,
            multipleAccountLabelText: "home",
            recipientPhoneNumber: "+17035559901",
            recipientUUID: address.uuid?.uuidString
        )
        createAccounts([account])
        let contactsManager = self.contactsManager as! OWSContactsManager
        read { transaction in
            let actual = contactsManager.phoneNumber(for: address, transaction: transaction)
            XCTAssertEqual(actual, "+17035559901")
        }
    }

    func testGetPhoneNumbersFromAddresses() {
        let addresses = [
            SignalServiceAddress(phoneNumber: "+17035559901"),
            SignalServiceAddress(phoneNumber: "+17035559902"),
            SignalServiceAddress(uuid: UUID())
        ]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumbers(for: addresses, transaction: transaction)
            let expected = ["+17035559901", "+17035559902", nil]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetPhoneNumbersFromProfiles() {
        let aliceServiceId = ServiceId(UUID())
        let aliceAddress = SignalServiceAddress(aliceServiceId)
        let aliceAccount = makeAccount(address: aliceAddress, phoneNumber: "+17035559901")

        let bobServiceId = ServiceId(UUID())
        let bobAddress = SignalServiceAddress(bobServiceId)
        let bobAccount = makeAccount(address: bobAddress, phoneNumber: "+17035559902")

        let bogusAddress = SignalServiceAddress(uuid: UUID())

        createRecipients([aliceServiceId, bobServiceId])
        createAccounts([aliceAccount, bobAccount])

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumbers(
                for: [aliceAddress, bogusAddress, bobAddress],
                transaction: transaction
            )
            let expected = [aliceAccount.recipientPhoneNumber, nil, bobAccount.recipientPhoneNumber]
            XCTAssertEqual(actual, expected)
        }
    }

    // MARK: - Display Names

    func testGetDisplayNamesWithCachedContactNames() {
        let serviceIds = [ServiceId(UUID()), ServiceId(UUID())]
        let addresses = serviceIds.map { SignalServiceAddress($0) }

        createRecipients(serviceIds)
        let accounts = [
            makeAccount(address: addresses[0], phoneNumber: nil, name: "Alice Aliceson"),
            makeAccount(address: addresses[1], phoneNumber: nil, name: "Bob Bobson")
        ]
        createAccounts(accounts)

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithProfileFullNames() {
        let addresses = [SignalServiceAddress(uuid: UUID()), SignalServiceAddress(uuid: UUID())]
        (self.profileManager as! OWSFakeProfileManager).fakeDisplayNames = [
            addresses[0]: "Alice Aliceson",
            addresses[1]: "Bob Bobson"
        ]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson", "Bob Bobson"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithPhoneNumbers() {
        let addresses = [
            SignalServiceAddress(phoneNumber: "+17035559900"),
            SignalServiceAddress(phoneNumber: "+17035559901")
        ]
        // Prevent default fake name from being used.
        (self.profileManager as! OWSFakeProfileManager).fakeDisplayNames = [:]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["+17035559900", "+17035559901"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithUserNames() {
        let aliceAci = ServiceId(UUID())
        let bobAci = ServiceId(UUID())

        let addresses = [SignalServiceAddress(aliceAci), SignalServiceAddress(bobAci)]

        // Store some fake usernames.

        dbV2.write { transaction in
            mockUsernameLookupMananger.saveUsername("alice", forAci: aliceAci, transaction: transaction)
            mockUsernameLookupMananger.saveUsername("bob", forAci: bobAci, transaction: transaction)
        }

        // Prevent default fake names from being used.
        (profileManager as! OWSFakeProfileManager).fakeDisplayNames = [:]

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["alice", "bob"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesUnknown() {
        let addresses = [SignalServiceAddress(uuid: UUID()), SignalServiceAddress(uuid: UUID())]

        // Intentionally do not set any mock usernames. Additionally, prevent
        // default fake names from being used.
        (profileManager as! OWSFakeProfileManager).fakeDisplayNames = [:]

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Unknown", "Unknown"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesMixed() {
        let aliceServiceId = ServiceId(UUID())
        let aliceAddress = SignalServiceAddress(aliceServiceId)
        let aliceAccount = makeAccount(address: aliceAddress, phoneNumber: nil, name: "Alice Aliceson")
        createRecipients([aliceServiceId])
        createAccounts([aliceAccount])

        let bobAddress = SignalServiceAddress(uuid: UUID())
        (profileManager as! OWSFakeProfileManager).fakeDisplayNames = [bobAddress: "Bob Bobson"]

        let carolAddress = SignalServiceAddress(phoneNumber: "+17035559900")

        let daveServiceId = ServiceId(UUID())
        let daveAddress = SignalServiceAddress(daveServiceId)
        dbV2.write { transaction in
            mockUsernameLookupMananger.saveUsername("dave", forAci: daveServiceId, transaction: transaction)
        }

        let eveAddress = SignalServiceAddress(uuid: UUID())

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let addresses = [aliceAddress, bobAddress, carolAddress, daveAddress, eveAddress]
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson", "+17035559900", "dave", "Unknown"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testSinglePartName() {
        let serviceIds = [ServiceId(UUID()), ServiceId(UUID())]
        let addresses = serviceIds.map { SignalServiceAddress($0) }
        createRecipients(serviceIds)
        let accounts = [
            makeAccount(address: addresses[0], phoneNumber: nil, name: "Alice"),
            makeAccount(address: addresses[1], phoneNumber: nil, name: "Bob")
        ]
        createAccounts(accounts)

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice (home)", "Bob (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    // MARK: - Cached Contact Names

    func testCachedContactNamesWithAccounts() {
        let serviceIds = [ServiceId(UUID()), ServiceId(UUID())]
        let addresses = serviceIds.map { SignalServiceAddress($0) }
        createRecipients(serviceIds)
        let accounts = [
            makeAccount(address: addresses[0], phoneNumber: nil, name: "Alice Aliceson"),
            makeAccount(address: addresses[1], phoneNumber: nil, name: "Bob Bobson")
        ]
        createAccounts(accounts)
        let contactsManager = makeContactsManager()
        read { transaction in
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testCachedContactNamesWithNonSignalContacts() {
        let aliceAddress = SignalServiceAddress(phoneNumber: "+17035550000")
        let bobAddress = SignalServiceAddress(phoneNumber: "+17035550001")
        createContacts([
            makeContact(address: aliceAddress, name: "Alice Aliceson"),
            makeContact(address: bobAddress, name: "Bob Bobson")
        ])
        let contactsManager = makeContactsManager()
        read { transaction in
            let addresses = [aliceAddress, bobAddress]
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson", "Bob Bobson"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testCachedContactNameWithNonSignalContactsLackingPhoneNumbers() {
        let addresses = [SignalServiceAddress(uuid: UUID()), SignalServiceAddress(uuid: UUID())]
        let contactsManager = makeContactsManager()
        read { transaction in
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            XCTAssertEqual(actual, [nil, nil])
        }
    }

    func testCachedContactNameMixed() {
        // Register alice with an account that has a full name.
        let aliceServiceId = ServiceId(UUID())
        let aliceAddress = SignalServiceAddress(aliceServiceId)
        let aliceAccount = makeAccount(address: aliceAddress, phoneNumber: nil, name: "Alice Aliceson")
        createRecipients([aliceServiceId])
        createAccounts([aliceAccount])

        // Register bob as a non-Signal contact.
        let bobAddress = SignalServiceAddress(phoneNumber: "+17035550001")
        createContacts([makeContact(address: bobAddress, name: "Bob Bobson")])

        // Who the heck is Chuck?
        let chuckAddress = SignalServiceAddress(uuid: UUID())

        let contactsManager = makeContactsManager()
        read { transaction in
            let addresses = [aliceAddress, bobAddress, chuckAddress]
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson", nil]
            XCTAssertEqual(actual, expected)
        }
    }
}
