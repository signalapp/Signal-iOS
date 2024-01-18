//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import XCTest

@testable import SignalMessaging

class ProfileManagerTest: XCTestCase {
    func testNormalizeRecipientInProfileWhitelist() {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000aaa")
        let phoneNumber = E164("+16505550100")!
        let pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-000000000bbb")

        let serviceIdStore = InMemoryKeyValueStore(collection: "")
        let phoneNumberStore = InMemoryKeyValueStore(collection: "")

        func normalizeRecipient(_ recipient: SignalRecipient) {
            MockDB().write { tx in
                OWSProfileManager.swift_normalizeRecipientInProfileWhitelist(
                    recipient,
                    serviceIdStore: serviceIdStore,
                    phoneNumberStore: phoneNumberStore,
                    tx: tx
                )
            }
        }

        // Don't add any values unless one is already present.
        MockDB().read { tx in
            normalizeRecipient(SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber))
            XCTAssertFalse(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertFalse(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }

        // Move the PNI identifier to the phone number.
        MockDB().write { tx in
            serviceIdStore.setBool(true, key: pni.serviceIdUppercaseString, transaction: tx)
            normalizeRecipient(SignalRecipient(aci: nil, pni: pni, phoneNumber: phoneNumber))
            XCTAssertFalse(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertTrue(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }

        // Clear lower priority identifiers when multiple are present.
        MockDB().write { tx in
            serviceIdStore.setBool(true, key: aci.serviceIdUppercaseString, transaction: tx)
            normalizeRecipient(SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber))
            XCTAssertTrue(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertFalse(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }

        // Keep the highest priority identifier if it's already present.
        MockDB().write { tx in
            normalizeRecipient(SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber))
            XCTAssertTrue(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertFalse(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }
    }

    func testEncodeDecodeProfileChanges() throws {
        let testCases: [(PendingProfileUpdate, String)] = [
            (
                PendingProfileUpdate(
                    profileGivenName: .setTo("Alice"),
                    profileFamilyName: .setTo("Johnson"),
                    profileBio: .setTo("A short bio."),
                    profileBioEmoji: .setTo("💙"),
                    profileAvatarData: .setTo(Data(1...3)),
                    visibleBadgeIds: .setTo(["BOOST"]),
                    userProfileWriter: .registration
                ),
                "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEA8LDCEiIyQlJicsLTM3ODxVJG51bGzaDQ4PEBESExQVFhcYGRobHB0eHyBfEA9wcm9maWxlQmlvRW1vamlacHJvZmlsZUJpb1YkY2xhc3NSaWRfEBh1bnNhdmVkUm90YXRlZFByb2ZpbGVLZXlfEBF1c2VyUHJvZmlsZVdyaXRlcl8QD3Zpc2libGVCYWRnZUlkc18QEXByb2ZpbGVBdmF0YXJEYXRhXxARcHJvZmlsZUZhbWlseU5hbWVfEBBwcm9maWxlR2l2ZW5OYW1lgAaABYAOgAKACxAEgAiAB4AEgANfECQwMDAwMDAwMC0wMDAwLTQwMDAtQTAwMC0wMDAwMDAwMDAwMDBVQWxpY2VXSm9obnNvblxBIHNob3J0IGJpby5i2D3cmUMBAgPSKA8pK1pOUy5vYmplY3RzoSqACYAKVUJPT1NU0i4vMDFaJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU0FycmF5ojAyWE5TT2JqZWN00jQPNTZXa2V5RGF0YYAMgA1PECABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fINIuLzk6XE9XU0FFUzI1NktleaI7MlxPV1NBRVMyNTZLZXnSLi89Pl8QJFNpZ25hbE1lc3NhZ2luZy5QZW5kaW5nUHJvZmlsZVVwZGF0ZaI/Ml8QJFNpZ25hbE1lc3NhZ2luZy5QZW5kaW5nUHJvZmlsZVVwZGF0ZQAIABEAGgAkACkAMgA3AEkATABRAFMAZQBrAIAAkgCdAKQApwDCANYA6AD8ARABIwElAScBKQErAS0BLwExATMBNQE3AV4BZAFsAXkBfgGCAYcBkgGUAZYBmAGeAaMBrgG3Ab8BwgHLAdAB2AHaAdwB/wIEAhECFAIhAiYCTQJQAAAAAAAAAgEAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAnc="
            ),
            (
                PendingProfileUpdate(
                    profileGivenName: .setTo("Alice"),
                    profileFamilyName: .setTo("Johnson"),
                    profileBio: .setTo("A short bio."),
                    profileBioEmoji: .setTo("💙"),
                    profileAvatarData: .setTo(Data(1...3)),
                    visibleBadgeIds: .setTo(["BOOST"]),
                    userProfileWriter: .registration
                ),
                "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGsCwwfICEiIyQlKisxVSRudWxs2Q0ODxAREhMUFRYXGBkaGxwdHl8QD3Byb2ZpbGVCaW9FbW9qaVpwcm9maWxlQmlvViRjbGFzc1JpZF8QEXVzZXJQcm9maWxlV3JpdGVyXxAPdmlzaWJsZUJhZGdlSWRzXxARcHJvZmlsZUF2YXRhckRhdGFfEBFwcm9maWxlRmFtaWx5TmFtZV8QEHByb2ZpbGVHaXZlbk5hbWWABoAFgAuAAhAEgAiAB4AEgANfECQwMDAwMDAwMC0wMDAwLTQwMDAtQTAwMC0wMDAwMDAwMDAwMDBVQWxpY2VXSm9obnNvblxBIHNob3J0IGJpby5i2D3cmUMBAgPSJg8nKVpOUy5vYmplY3RzoSiACYAKVUJPT1NU0iwtLi9aJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU0FycmF5oi4wWE5TT2JqZWN00iwtMjNfECRTaWduYWxNZXNzYWdpbmcuUGVuZGluZ1Byb2ZpbGVVcGRhdGWiNDBfECRTaWduYWxNZXNzYWdpbmcuUGVuZGluZ1Byb2ZpbGVVcGRhdGUACAARABoAJAApADIANwBJAEwAUQBTAGAAZgB5AIsAlgCdAKAAtADGANoA7gEBAQMBBQEHAQkBCwENAQ8BEQETAToBQAFIAVUBWgFeAWMBbgFwAXIBdAF6AX8BigGTAZsBngGnAawB0wHWAAAAAAAAAgEAAAAAAAAANQAAAAAAAAAAAAAAAAAAAf0="
            ),
            (
                PendingProfileUpdate(
                    profileGivenName: .noChange,
                    profileFamilyName: .noChange,
                    profileBio: .noChange,
                    profileBioEmoji: .noChange,
                    profileAvatarData: .noChange,
                    visibleBadgeIds: .noChange,
                    userProfileWriter: .localUser
                ),
                "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwdHlUkbnVsbNgNDg8QERITFBUWFxcXFxsXViRjbGFzc1JpZF8QFnByb2ZpbGVCaW9FbW9qaUNoYW5nZWRfEBhwcm9maWxlRmFtaWx5TmFtZUNoYW5nZWRfEBFwcm9maWxlQmlvQ2hhbmdlZF8QF3Byb2ZpbGVHaXZlbk5hbWVDaGFuZ2VkXxARdXNlclByb2ZpbGVXcml0ZXJfEBhwcm9maWxlQXZhdGFyRGF0YUNoYW5nZWSAA4ACCAgICBAACF8QJDAwMDAwMDAwLTAwMDAtNDAwMC1BMDAwLTAwMDAwMDAwMDAwMNIfICEiWiRjbGFzc25hbWVYJGNsYXNzZXNfECRTaWduYWxNZXNzYWdpbmcuUGVuZGluZ1Byb2ZpbGVVcGRhdGWiIyRfECRTaWduYWxNZXNzYWdpbmcuUGVuZGluZ1Byb2ZpbGVVcGRhdGVYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFgAXgBvAHYAeQCSAK0AwQDbAO8BCgEMAQ4BDwEQAREBEgEUARUBPAFBAUwBVQF8AX8BpgAAAAAAAAIBAAAAAAAAACUAAAAAAAAAAAAAAAAAAAGv"
            ),
        ]
        let expectedId = UUID(uuidString: "00000000-0000-4000-A000-000000000000")!
        for (expectedValue, encodedValue) in testCases {
            // Test that it can be encoded/decoded.
            let decodedEncodedValue = try Self.deserialize(data: Self.serialize(expectedValue))
            XCTAssertEqual(decodedEncodedValue.id, expectedValue.id)
            XCTAssertEqual(decodedEncodedValue.profileGivenName, expectedValue.profileGivenName)
            XCTAssertEqual(decodedEncodedValue.profileFamilyName, expectedValue.profileFamilyName)
            XCTAssertEqual(decodedEncodedValue.profileBio, expectedValue.profileBio)
            XCTAssertEqual(decodedEncodedValue.profileBioEmoji, expectedValue.profileBioEmoji)
            XCTAssertEqual(decodedEncodedValue.profileAvatarData, expectedValue.profileAvatarData)
            XCTAssertEqual(decodedEncodedValue.visibleBadgeIds, expectedValue.visibleBadgeIds)
            XCTAssertEqual(decodedEncodedValue.userProfileWriter, expectedValue.userProfileWriter)

            // Test a stable decoding.
            let decodedValue = try Self.deserialize(data: XCTUnwrap(Data(base64Encoded: encodedValue)))
            XCTAssertEqual(decodedValue.id, expectedId)
            XCTAssertEqual(decodedValue.profileGivenName, expectedValue.profileGivenName)
            XCTAssertEqual(decodedValue.profileFamilyName, expectedValue.profileFamilyName)
            XCTAssertEqual(decodedValue.profileBio, expectedValue.profileBio)
            XCTAssertEqual(decodedValue.profileBioEmoji, expectedValue.profileBioEmoji)
            XCTAssertEqual(decodedValue.profileAvatarData, expectedValue.profileAvatarData)
            XCTAssertEqual(decodedValue.visibleBadgeIds, expectedValue.visibleBadgeIds)
            XCTAssertEqual(decodedValue.userProfileWriter, expectedValue.userProfileWriter)
        }
    }

    private static func serialize(_ pendingProfileUpdate: PendingProfileUpdate) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: pendingProfileUpdate, requiringSecureCoding: false)
    }

    private static func deserialize(data: Data) throws -> PendingProfileUpdate {
        try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: PendingProfileUpdate.self, from: data, requiringSecureCoding: false))
    }
}
