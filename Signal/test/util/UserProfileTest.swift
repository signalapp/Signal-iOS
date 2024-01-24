//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class UserProfileTest: SignalBaseTest {
    override func setUp() {
        super.setUp()
        // Create local account.
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
    }

    func testUserProfileForAci() {
        let aci = Aci.randomForTesting()
        let address = SignalServiceAddress(aci)
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getUserProfile(for: address, transaction: transaction)
            XCTAssertEqual(actual?.serviceIdString, aci.serviceIdUppercaseString)
        }
        read { transaction in
            let actual = OWSUserProfile.getUserProfile(for: SignalServiceAddress.randomForTesting(), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfileForPni() throws {
        let pni = Pni.randomForTesting()
        let address = SignalServiceAddress(pni)
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getUserProfile(for: address, transaction: transaction)
            XCTAssertEqual(actual?.serviceIdString, pni.serviceIdUppercaseString)
        }
        read { transaction in
            let actual = OWSUserProfile.getUserProfile(for: SignalServiceAddress.randomForTesting(), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfilesForServiceIds() {
        let addresses = [
            SignalServiceAddress.randomForTesting(),
            SignalServiceAddress.randomForTesting()
        ]
        let profiles = addresses.map { OWSUserProfile(address: $0) }
        write { transaction in
            for profile in profiles {
                profile.anyInsert(transaction: transaction)
            }
        }
        read { transaction in
            let bogusAddresses = [SignalServiceAddress.randomForTesting()]
            let actual = SignalServiceKit.OWSUserProfile.getFor(keys: addresses + bogusAddresses, transaction: transaction)
            let expected = profiles + [nil]
            XCTAssertEqual(actual.map { $0?.serviceIdString }, expected.map { $0?.serviceIdString })
        }
    }

    func testUserProfileForPhoneNumber() {
        let address = SignalServiceAddress(phoneNumber: "+17035550000")
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getUserProfile(for: address, transaction: transaction)
            XCTAssertEqual(actual?.phoneNumber, "+17035550000")
        }
        read { transaction in
            let actual = OWSUserProfile.getUserProfile(for: SignalServiceAddress(phoneNumber: "+17035550001"), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfilesForPhoneNumbers() {
        let addresses = [
            SignalServiceAddress(phoneNumber: "+17035550000"),
            SignalServiceAddress(phoneNumber: "+17035550001")
        ]
        let profiles = addresses.map { OWSUserProfile(address: $0) }
        write { transaction in
            for profile in profiles {
                profile.anyInsert(transaction: transaction)
            }
        }
        read { transaction in
            let bogusAddresses = [SignalServiceAddress(phoneNumber: "+17035550002")]
            let actual = SignalServiceKit.OWSUserProfile.getFor(keys: addresses + bogusAddresses, transaction: transaction)
            let expected = profiles + [nil]
            XCTAssertEqual(actual.map { $0?.phoneNumber }, expected.map { $0?.phoneNumber })
        }
    }
}

final class UserProfile2Test: XCTestCase {
    func testDecodeStableRow() throws {
        let db = InMemoryDB()
        try db.write { tx in
            try InMemoryDB.shimOnlyBridge(tx).db.execute(sql: """
                INSERT INTO "model_OWSUserProfile" (
                    "id","recordType","uniqueId","avatarFileName","avatarUrlPath","profileKey","profileName","recipientPhoneNumber","recipientUUID","familyName","lastFetchDate","lastMessagingDate","bio","bioEmoji","profileBadgeInfo","isStoriesCapable","canReceiveGiftBadges","isPniCapable"
                ) VALUES (
                    1,
                    41,
                    '00000000-0000-4000-8000-00000000000A',
                    NULL,
                    NULL,
                    X'62706c6973743030d40102030405061415582476657273696f6e58246f626a65637473592461726368697665725424746f7012000186a0a407080d0e55246e756c6cd2090a0b0c576b6579446174615624636c617373800280034f10200102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20d20f1011125824636c61737365735a24636c6173736e616d65a212135c4f57534145533235364b6579584e534f626a6563745f100f4e534b657965644172636869766572d1161754726f6f74800108111a232d32373c42474f56585a7d828b9699a6afc1c4c900000000000001010000000000000018000000000000000000000000000000cb',
                    'Bob',
                    'kLocalProfileUniqueId',
                    NULL,
                    'Smith',
                    1700000000.0000000000,
                    NULL,
                    'Speak',
                    '😂',
                    CAST('[]' AS BLOB),
                    0,
                    0,
                    0
                ),
                (
                    2,
                    41,
                    '00000000-0000-4000-8000-00000000000B',
                    '00000000-0000-4000-8000-00000000000C.jpg',
                    'profiles/AAAAAAAAAAAAAAAAAAAAAA==',
                    X'02030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021',
                    'Alice',
                    '+16505550102',
                    '00000000-0000-4000-8000-00000000000D',
                    'Johnson',
                    1700000000.0000000000,
                    1702000000.0000000000,
                    'Freely',
                    '😀',
                    CAST('[{"badgeId":"BOOST"}]' AS BLOB),
                    1,
                    1,
                    1
                );
            """)
        }
        try db.read { tx in
            let userProfiles = try OWSUserProfile.fetchAll(InMemoryDB.shimOnlyBridge(tx).db)
            XCTAssertEqual(userProfiles.count, 2)

            XCTAssertEqual(userProfiles[0].id, 1)
            XCTAssertEqual(userProfiles[0].uniqueId, "00000000-0000-4000-8000-00000000000A")
            XCTAssertEqual(userProfiles[0].serviceIdString, nil)
            XCTAssertEqual(userProfiles[0].phoneNumber, OWSUserProfile.Constants.localProfilePhoneNumber)
            XCTAssertEqual(userProfiles[0].avatarFileName, nil)
            XCTAssertEqual(userProfiles[0].avatarUrlPath, nil)
            XCTAssertEqual(userProfiles[0].profileKey?.keyData, Data(1...32))
            XCTAssertEqual(userProfiles[0].givenName, "Bob")
            XCTAssertEqual(userProfiles[0].familyName, "Smith")
            XCTAssertEqual(userProfiles[0].bio, "Speak")
            XCTAssertEqual(userProfiles[0].bioEmoji, "😂")
            XCTAssertEqual(userProfiles[0].badges, [])
            XCTAssertEqual(userProfiles[0].lastFetchDate, Date(timeIntervalSince1970: 1700000000))
            XCTAssertEqual(userProfiles[0].lastMessagingDate, nil)
            XCTAssertEqual(userProfiles[0].isPniCapable, false)

            XCTAssertEqual(userProfiles[1].id, 2)
            XCTAssertEqual(userProfiles[1].uniqueId, "00000000-0000-4000-8000-00000000000B")
            XCTAssertEqual(userProfiles[1].serviceIdString, "00000000-0000-4000-8000-00000000000D")
            XCTAssertEqual(userProfiles[1].phoneNumber, "+16505550102")
            XCTAssertEqual(userProfiles[1].avatarFileName, "00000000-0000-4000-8000-00000000000C.jpg")
            XCTAssertEqual(userProfiles[1].avatarUrlPath, "profiles/AAAAAAAAAAAAAAAAAAAAAA==")
            XCTAssertEqual(userProfiles[1].profileKey?.keyData, Data(2...33))
            XCTAssertEqual(userProfiles[1].givenName, "Alice")
            XCTAssertEqual(userProfiles[1].familyName, "Johnson")
            XCTAssertEqual(userProfiles[1].bio, "Freely")
            XCTAssertEqual(userProfiles[1].bioEmoji, "😀")
            XCTAssertEqual(userProfiles[1].badges, [OWSUserProfileBadgeInfo(badgeId: "BOOST")])
            XCTAssertEqual(userProfiles[1].lastFetchDate, Date(timeIntervalSince1970: 1700000000))
            XCTAssertEqual(userProfiles[1].lastMessagingDate, Date(timeIntervalSince1970: 1702000000))
            XCTAssertEqual(userProfiles[1].isPniCapable, true)
        }
    }

    func testNameComponent() {
        XCTAssertEqual(
            OWSUserProfile.NameComponent(truncating: String(repeating: "A", count: 27))?.stringValue.rawValue,
            String(repeating: "A", count: 26)
        )
        XCTAssertEqual(
            OWSUserProfile.NameComponent(truncating: String(repeating: "👨‍👩‍👧‍👦", count: 6))?.stringValue.rawValue,
            String(repeating: "👨‍👩‍👧‍👦", count: 5)
        )
        // If you strip and then truncate this string, the resulting string would
        // become empty if you strip it again. While you'd normally expect a
        // stripped string to start with a non-strippable character, control
        // characters are treated fairly strangely.
        XCTAssertNil(OWSUserProfile.NameComponent(truncating: "\0" + String(repeating: " ", count: 25) + "A"))
    }
}
