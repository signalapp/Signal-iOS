//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalMessaging
@testable import SignalServiceKit

class OWSContactsManagerTest: SignalBaseTest {
    private let dbV2: MockDB = .init()

    private let mockUsernameLookupMananger: MockUsernameLookupManager = .init()

    override func setUp() {
        super.setUp()

        // Create local account.
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }

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
                .build(contacts: contacts, localNumber: LocalIdentifiers.forUnitTests.phoneNumber),
                localNumber: LocalIdentifiers.forUnitTests.phoneNumber,
                transaction: transaction
            )
        }
    }

    private func makeAccount(
        serviceId: ServiceId,
        phoneNumber: String?,
        name: String? = nil
    ) -> SignalAccount {
        let contact = name.map { name -> Contact in
            makeContact(
                address: SignalServiceAddress(
                    serviceId: serviceId,
                    phoneNumber: phoneNumber
                ),
                name: name
            )
        }

        return SignalAccount(
            contact: contact,
            contactAvatarHash: nil,
            multipleAccountLabelText: "home",
            recipientPhoneNumber: phoneNumber,
            recipientServiceId: serviceId
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

    func testGetPhoneNumberFromAciProfile() {
        let aci = Aci.randomForTesting()
        let account = SignalAccount(
            contact: nil,
            contactAvatarHash: nil,
            multipleAccountLabelText: "home",
            recipientPhoneNumber: "+17035559901",
            recipientServiceId: aci
        )
        createAccounts([account])
        let contactsManager = self.contactsManager as! OWSContactsManager
        read { transaction in
            let actual = contactsManager.phoneNumber(for: SignalServiceAddress(aci), transaction: transaction)
            XCTAssertEqual(actual, "+17035559901")
        }
    }

    func testGetPhoneNumberFromPniProfile() {
        let pni = Pni.randomForTesting()
        let account = SignalAccount(
            contact: nil,
            contactAvatarHash: nil,
            multipleAccountLabelText: "home",
            recipientPhoneNumber: "+17035559901",
            recipientServiceId: pni
        )
        createAccounts([account])
        let contactsManager = self.contactsManager as! OWSContactsManager
        read { transaction in
            let actual = contactsManager.phoneNumber(
                for: SignalServiceAddress(serviceIdString: pni.serviceIdUppercaseString),
                transaction: transaction
            )
            XCTAssertEqual(actual, "+17035559901")
        }
    }

    func testGetPhoneNumbersFromAddresses() {
        let addresses = [
            SignalServiceAddress(phoneNumber: "+17035559901"),
            SignalServiceAddress(phoneNumber: "+17035559902"),
            SignalServiceAddress.randomForTesting()
        ]
        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumbers(for: addresses, transaction: transaction)
            let expected = ["+17035559901", "+17035559902", nil]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetPhoneNumbersFromProfiles() {
        let aliceAci = Aci.randomForTesting()
        let aliceAddress = SignalServiceAddress(serviceId: aliceAci, phoneNumber: "+17035559901")

        let bobAci = Aci.randomForTesting()
        let bobAddress = SignalServiceAddress(serviceId: bobAci, phoneNumber: "+17035559902")

        let bogusAddress = SignalServiceAddress.randomForTesting()

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let actual = contactsManager.phoneNumbers(
                for: [aliceAddress, bogusAddress, bobAddress],
                transaction: transaction
            )
            let expected = [aliceAddress.phoneNumber, nil, bobAddress.phoneNumber]
            XCTAssertEqual(actual, expected)
        }
    }

    // MARK: - Display Names

    func testGetDisplayNamesWithCachedContactNames() {
        let serviceIds = [Aci.randomForTesting(), Aci.randomForTesting()]
        let addresses = serviceIds.map { SignalServiceAddress($0) }

        createRecipients(serviceIds)
        let accounts = [
            makeAccount(serviceId: serviceIds[0], phoneNumber: nil, name: "Alice Aliceson"),
            makeAccount(serviceId: serviceIds[1], phoneNumber: nil, name: "Bob Bobson")
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
        let addresses = [SignalServiceAddress.randomForTesting(), SignalServiceAddress.randomForTesting()]
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
        let aliceAci = Aci.randomForTesting()
        let bobAci = Aci.randomForTesting()

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
        let addresses = [SignalServiceAddress.randomForTesting(), SignalServiceAddress.randomForTesting()]

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
        let aliceAci = Aci.randomForTesting()
        let aliceAddress = SignalServiceAddress(aliceAci)
        let aliceAccount = makeAccount(serviceId: aliceAci, phoneNumber: nil, name: "Alice Aliceson")
        createRecipients([aliceAci])
        createAccounts([aliceAccount])

        let bobAddress = SignalServiceAddress.randomForTesting()
        (profileManager as! OWSFakeProfileManager).fakeDisplayNames = [bobAddress: "Bob Bobson"]

        let carolAddress = SignalServiceAddress(phoneNumber: "+17035559900")

        let daveAci = Aci.randomForTesting()
        let daveAddress = SignalServiceAddress(daveAci)
        dbV2.write { transaction in
            mockUsernameLookupMananger.saveUsername("dave", forAci: daveAci, transaction: transaction)
        }

        let eveAddress = SignalServiceAddress.randomForTesting()

        read { transaction in
            let contactsManager = self.contactsManager as! OWSContactsManager
            let addresses = [aliceAddress, bobAddress, carolAddress, daveAddress, eveAddress]
            let actual = contactsManager.displayNames(for: addresses, transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson", "+17035559900", "dave", "Unknown"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testSinglePartName() {
        let serviceIds = [Aci.randomForTesting(), Aci.randomForTesting()]
        let addresses = serviceIds.map { SignalServiceAddress($0) }
        createRecipients(serviceIds)
        let accounts = [
            makeAccount(serviceId: serviceIds[0], phoneNumber: nil, name: "Alice"),
            makeAccount(serviceId: serviceIds[1], phoneNumber: nil, name: "Bob")
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
        let serviceIds = [Aci.randomForTesting(), Aci.randomForTesting()]
        let addresses = serviceIds.map { SignalServiceAddress($0) }
        createRecipients(serviceIds)
        let accounts = [
            makeAccount(serviceId: serviceIds[0], phoneNumber: nil, name: "Alice Aliceson"),
            makeAccount(serviceId: serviceIds[1], phoneNumber: nil, name: "Bob Bobson")
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
        let addresses = [SignalServiceAddress.randomForTesting(), SignalServiceAddress.randomForTesting()]
        let contactsManager = makeContactsManager()
        read { transaction in
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            XCTAssertEqual(actual, [nil, nil])
        }
    }

    func testCachedContactNameMixed() {
        // Register alice with an account that has a full name.
        let aliceAci = Aci.randomForTesting()
        let aliceAddress = SignalServiceAddress(aliceAci)
        let aliceAccount = makeAccount(serviceId: aliceAci, phoneNumber: nil, name: "Alice Aliceson")
        createRecipients([aliceAci])
        createAccounts([aliceAccount])

        // Register bob as a non-Signal contact.
        let bobAddress = SignalServiceAddress(phoneNumber: "+17035550001")
        createContacts([makeContact(address: bobAddress, name: "Bob Bobson")])

        // Who the heck is Chuck?
        let chuckAddress = SignalServiceAddress.randomForTesting()

        let contactsManager = makeContactsManager()
        read { transaction in
            let addresses = [aliceAddress, bobAddress, chuckAddress]
            let actual = contactsManager.cachedContactNames(for: AnySequence(addresses), transaction: transaction)
            let expected = ["Alice Aliceson (home)", "Bob Bobson", nil]
            XCTAssertEqual(actual, expected)
        }
    }
}
