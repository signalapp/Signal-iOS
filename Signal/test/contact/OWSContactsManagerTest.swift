//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalServiceKit

class OWSContactsManagerTest: SignalBaseTest {
    private let dbV2: InMemoryDB = .init()

    private let mockUsernameLookupMananger: MockUsernameLookupManager = .init()
    private let mockNicknameManager = MockNicknameManager()
    private let mockRecipientDatabaseTable = MockRecipientDatabaseTable()

    override func setUp() {
        super.setUp()

        // Create local account.
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }

        // Replace the fake contacts manager with the real one just for this test.
        SSKEnvironment.shared.setContactManagerForUnitTests(makeContactsManager())
    }

    override func tearDown() {
        mockUsernameLookupMananger.clearAllUsernames()
    }

    private func makeContactsManager() -> OWSContactsManager {
        return OWSContactsManager(
            appReadiness: AppReadinessMock(),
            nicknameManager: mockNicknameManager,
            recipientDatabaseTable: mockRecipientDatabaseTable,
            usernameLookupManager: mockUsernameLookupMananger
        )
    }

    private func makeAndInsertRecipient(address: SignalServiceAddress) -> SignalRecipient {
        let recipient = SignalRecipient(
            aci: address.aci,
            pni: nil,
            phoneNumber: address.e164
        )
        self.dbV2.write { tx in
            mockRecipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        }
        return recipient
    }

    private func createRecipients(_ serviceIds: [ServiceId]) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipientManager = DependenciesBridge.shared.recipientManager
        write { tx in
            for serviceId in serviceIds {
                recipientManager.markAsRegisteredAndSave(
                    recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write),
                    shouldUpdateStorageService: false,
                    tx: tx.asV2Write
                )
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

    private func makeAccount(
        serviceId: ServiceId,
        phoneNumber: E164,
        fullName: String
    ) -> SignalAccount {
        let parts = fullName.components(separatedBy: " ")
        return SignalAccount(
            recipientPhoneNumber: phoneNumber.stringValue,
            recipientServiceId: serviceId,
            multipleAccountLabelText: "home",
            cnContactId: nil,
            givenName: parts.first!,
            familyName: parts.dropFirst().first ?? "",
            nickname: "",
            fullName: fullName,
            contactAvatarHash: nil
        )
    }

    private func makeUserProfile(givenName: String, familyName: String) -> OWSUserProfile {
        return OWSUserProfile(
            id: nil,
            uniqueId: "",
            serviceIdString: nil,
            phoneNumber: nil,
            avatarFileName: nil,
            avatarUrlPath: nil,
            profileKey: nil,
            givenName: givenName,
            familyName: familyName,
            bio: nil,
            bioEmoji: nil,
            badges: [],
            lastFetchDate: nil,
            lastMessagingDate: nil,
            isPhoneNumberShared: nil
        )
    }

    // MARK: - Display Names

    func testGetDisplayNamesWithNicknames() throws {
        let aliceAddress = SignalServiceAddress(phoneNumber: "+16505550101")
        let bobAddress = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550102")

        let aliceRecipient = makeAndInsertRecipient(address: aliceAddress)
        let bobRecipient = makeAndInsertRecipient(address: bobAddress)

        let aliceRecipientRowID = try XCTUnwrap(aliceRecipient.id)
        let bobRecipientRowID = try XCTUnwrap(bobRecipient.id)

        let aliceNickname = NicknameRecord(
            recipientRowID: aliceRecipientRowID,
            givenName: "Alice",
            familyName: "Doe",
            note: nil
        )
        let bobNickname = NicknameRecord(
            recipientRowID: bobRecipientRowID,
            givenName: "Bob",
            familyName: nil,
            note: nil
        )

        self.dbV2.write { tx in
            mockNicknameManager.insert(aliceNickname, tx: tx)
            mockNicknameManager.insert(bobNickname, tx: tx)
        }

        self.read { tx in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(
                for: [aliceAddress, bobAddress],
                tx: tx
            ).map { $0.resolvedValue() }
            let expected = ["Alice Doe", "Bob"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithCachedContactNames() {
        let addresses = [
            SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550100"),
            SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550101"),
        ]
        createRecipients(addresses.map { $0.serviceId! })
        createAccounts(zip(addresses, ["Alice Aliceson", "Bob Bobson"]).map { address, name in
            makeAccount(serviceId: address.serviceId!, phoneNumber: address.e164!, fullName: name)
        })

        read { transaction in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
            let expected = ["Alice Aliceson (home)", "Bob Bobson (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesWithProfileFullNames() {
        let addresses = [SignalServiceAddress.randomForTesting(), SignalServiceAddress.randomForTesting()]
        (SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager).fakeUserProfiles = [
            addresses[0]: makeUserProfile(givenName: "Alice", familyName: "Aliceson"),
            addresses[1]: makeUserProfile(givenName: "Bob", familyName: "Bobson"),
        ]
        read { transaction in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
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
        (SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager).fakeUserProfiles = [:]
        read { transaction in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
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
        (SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager).fakeUserProfiles = [:]

        read { transaction in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
            let expected = ["alice", "bob"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesUnknown() {
        let addresses = [SignalServiceAddress.randomForTesting(), SignalServiceAddress.randomForTesting()]

        // Intentionally do not set any mock usernames. Additionally, prevent
        // default fake names from being used.
        (SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager).fakeUserProfiles = [:]

        read { transaction in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
            let expected = ["Unknown", "Unknown"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetDisplayNamesMixed() throws {
        let aliceAci = Aci.randomForTesting()
        let aliceAddress = SignalServiceAddress(serviceId: aliceAci, phoneNumber: "+16505550100")
        let aliceAccount = makeAccount(serviceId: aliceAci, phoneNumber: aliceAddress.e164!, fullName: "Alice Aliceson")
        createRecipients([aliceAci])
        createAccounts([aliceAccount])

        let bobAddress = SignalServiceAddress.randomForTesting()
        (SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager).fakeUserProfiles = [
            bobAddress: makeUserProfile(givenName: "Bob", familyName: "Bobson"),
        ]

        let carolAddress = SignalServiceAddress(phoneNumber: "+17035559900")

        let daveAci = Aci.randomForTesting()
        let daveAddress = SignalServiceAddress(daveAci)
        dbV2.write { transaction in
            mockUsernameLookupMananger.saveUsername("dave", forAci: daveAci, transaction: transaction)
        }

        let eveAddress = SignalServiceAddress.randomForTesting()

        let feliciaAci = Aci.randomForTesting()
        let feliciaAddress = SignalServiceAddress(serviceId: feliciaAci, phoneNumber: "+16505550109")
        // Test that it doesn't show this account name
        let feliciaProfileName = UUID().uuidString
        let feliciaAccount = makeAccount(serviceId: feliciaAci, phoneNumber: feliciaAddress.e164!, fullName: feliciaProfileName)
        createAccounts([feliciaAccount])
        let feliciaRecipient = makeAndInsertRecipient(address: feliciaAddress)
        let feliciaRowID = try XCTUnwrap(feliciaRecipient.id)
        let feliciaNickname = NicknameRecord(
            recipientRowID: feliciaRowID,
            givenName: "Felicia",
            familyName: "Felicity",
            note: nil
        )
        dbV2.write { tx in
            mockNicknameManager.insert(feliciaNickname, tx: tx)
        }

        read { transaction in
            let addresses = [aliceAddress, bobAddress, carolAddress, daveAddress, eveAddress, feliciaAddress]
            let actual = SSKEnvironment.shared.contactManagerRef.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
            let expected = ["Alice Aliceson (home)", "Bob Bobson", "+17035559900", "dave", "Unknown", "Felicia Felicity"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testSinglePartName() {
        let addresses = [
            SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550100"),
            SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550101"),
        ]
        createRecipients(addresses.map { $0.serviceId! })
        createAccounts(zip(addresses, ["Alice", "Bob"]).map { address, name in
            makeAccount(serviceId: address.serviceId!, phoneNumber: address.e164!, fullName: name)
        })

        read { transaction in
            let contactsManager = SSKEnvironment.shared.contactManagerRef as! OWSContactsManager
            let actual = contactsManager.displayNames(for: addresses, tx: transaction).map { $0.resolvedValue() }
            let expected = ["Alice (home)", "Bob (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    // MARK: - Cached Contact Names

    func testCachedContactNamesWithAccounts() {
        let addresses = [
            SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550100"),
            SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+16505550101"),
        ]
        createRecipients(addresses.map { $0.serviceId! })
        createAccounts(zip(addresses, ["Alice Aliceson", "Bob Bobson"]).map { address, name in
            makeAccount(serviceId: address.serviceId!, phoneNumber: address.e164!, fullName: name)
        })
        let contactsManager = makeContactsManager()
        read { transaction in
            let actual = contactsManager.systemContactNames(for: addresses.map { $0.phoneNumber! }, tx: transaction).map { $0?.resolvedValue() }
            let expected = ["Alice Aliceson (home)", "Bob Bobson (home)"]
            XCTAssertEqual(actual, expected)
        }
    }

    func testCachedContactNameMixed() {
        // Register alice with an account that has a full name.
        let aliceAci = Aci.randomForTesting()
        let aliceAddress = SignalServiceAddress(serviceId: aliceAci, phoneNumber: "+16505550100")
        let aliceAccount = makeAccount(serviceId: aliceAci, phoneNumber: aliceAddress.e164!, fullName: "Alice Aliceson")
        createRecipients([aliceAci])
        createAccounts([aliceAccount])

        // Who the heck is Chuck?
        let chuckAci = Aci.randomForTesting()
        let chuckAddress = SignalServiceAddress(serviceId: chuckAci, phoneNumber: "+16505550101")

        let contactsManager = makeContactsManager()
        read { transaction in
            let addresses = [aliceAddress, chuckAddress]
            let actual = contactsManager.systemContactNames(for: addresses.map { $0.phoneNumber! }, tx: transaction).map { $0?.resolvedValue() }
            let expected = ["Alice Aliceson (home)", nil]
            XCTAssertEqual(actual, expected)
        }
    }
}
