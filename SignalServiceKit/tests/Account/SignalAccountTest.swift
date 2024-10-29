//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SignalAccountTest: XCTestCase {

    // MARK: - (De)Serialization Tests

    private let inMemoryDB = InMemoryDB()

    func testInMemoryDatabaseRoundTrip() {
        for (idx, (constant, _)) in SignalAccount.constants.enumerated() {
            inMemoryDB.insert(record: constant)

            guard let deserialized = inMemoryDB.fetchExactlyOne(modelType: SignalAccount.self) else {
                XCTFail("Failed to fetch constant \(idx)!")
                continue
            }

            do {
                try deserialized.validate(against: constant)
            } catch ValidatableModelError.failedToValidate {
                XCTFail("Failed to validate constant \(idx)!")
            } catch {
                XCTFail("Unexpected error while validating constant \(idx)!")
            }

            inMemoryDB.remove(model: deserialized)
        }
    }

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedJsonDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedJsonDataDecodes() {
        switch HardcodedDataTestMode.mode {
        case .printStrings:
            SignalAccount.printHardcodedJsonDataForConstants()
        case .runTest:
            for (idx, (constant, jsonData)) in SignalAccount.constants.enumerated() {
                do {
                    let decoded = try JSONDecoder().decode(SignalAccount.self, from: jsonData)
                    try constant.validate(against: decoded)
                } catch let error where error is DecodingError {
                    XCTFail("Failed to decode JSON model for constant \(idx): \(error)")
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate JSON-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }
            }
        }
    }

    /// This test ensures that json from the era before `SignalAccount`
    /// was an `SDSCodableModel` can still be decoded.
    func testHardcodedJsonLegacyDataDecodes() {
        for (idx, (constant, jsonData)) in SignalAccount.legacyConstants.enumerated() {
            do {
                let decoded = try JSONDecoder().decode(SignalAccount.self, from: jsonData)
                try constant.validate(against: decoded)
            } catch let error where error is DecodingError {
                XCTFail("Failed to decode JSON model for constant \(idx): \(error)")
            } catch ValidatableModelError.failedToValidate {
                XCTFail("Failed to validate JSON-decoded model for constant \(idx)")
            } catch {
                XCTFail("Unexpected error for constant \(idx)")
            }
        }
    }

    // MARK: - Display Name Tests

    func testContactNameComponents() {
        let signalAccount = SignalAccount(
            recipientPhoneNumber: "+16505550100",
            recipientServiceId: Aci.constantForTesting("00000000-0000-4000-A000-000000000000"),
            multipleAccountLabelText: "Mobile",
            cnContactId: nil,
            givenName: "Shabby",
            familyName: "Thesealion",
            nickname: "Shabs ",
            fullName: "Shabby Thesealion",
            contactAvatarHash: nil
        )

        let nameComponents = signalAccount.contactNameComponents()!
        XCTAssertEqual(nameComponents.givenName, "Shabby")
        XCTAssertEqual(nameComponents.familyName, "Thesealion")
        XCTAssertEqual(nameComponents.nickname, "Shabs")

        let systemContactName = DisplayName.SystemContactName(
            nameComponents: nameComponents,
            multipleAccountLabel: "Mobile"
        )

        XCTAssertEqual(
            systemContactName.resolvedValue(config: DisplayName.Config(shouldUseSystemContactNicknames: false)),
            "Shabby Thesealion (Mobile)"
        )
        XCTAssertEqual(
            systemContactName.resolvedValue(config: DisplayName.Config(shouldUseSystemContactNicknames: true)),
            "Shabs (Mobile)"
        )
    }

    func testFullNameOnly() {
        let signalAccount = SignalAccount(
            recipientPhoneNumber: "+16505550100",
            recipientServiceId: Aci.constantForTesting("00000000-0000-4000-A000-000000000000"),
            multipleAccountLabelText: nil,
            cnContactId: nil,
            givenName: "",
            familyName: "",
            nickname: "",
            fullName: "Company Name",
            contactAvatarHash: nil
        )

        let nameComponents = signalAccount.contactNameComponents()!
        XCTAssertEqual(nameComponents.givenName, "Company Name")
    }
}

extension SignalAccount: ValidatableModel {
    static let constants: [(SignalAccount, jsonData: Data)] = [
        (
            SignalAccount(
                recipientPhoneNumber: "+17735550199",
                recipientServiceId: Pni.constantForTesting("PNI:2405EEEA-9CFF-4FB4-A9D2-FBB473018D57"),
                multipleAccountLabelText: "boop",
                cnContactId: nil,
                givenName: "matata",
                familyName: "what",
                nickname: "a",
                fullName: "wonderful",
                contactAvatarHash: Data(repeating: 12, count: 12)
            ),
            Data(#"{"recipientPhoneNumber":"+17735550199","contactAvatarHash":"DAwMDAwMDAwMDAwM","recipientUUID":"PNI:2405EEEA-9CFF-4FB4-A9D2-FBB473018D57","contact":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGtCwwnKCkqKywyOTw\/QFUkbnVsbN0NDg8QERITFBUWFxgZGhscHR4fICEhIyEdHV8QD01UTE1vZGVsVmVyc2lvbllmaXJzdE5hbWVYbGFzdE5hbWVfEBdjb21wYXJhYmxlTmFtZUxhc3RGaXJzdFh1bmlxdWVJZF8QEnBob25lTnVtYmVyTmFtZU1hcFYkY2xhc3NfEBJwYXJzZWRQaG9uZU51bWJlcnNfEBR1c2VyVGV4dFBob25lTnVtYmVyc1hmdWxsTmFtZVZlbWFpbHNfEBdjb21wYXJhYmxlTmFtZUZpcnN0TGFzdFhuaWNrbmFtZYACgASAA4AFgAaAB4AMgAmACYALgAmABYAFEABUd2hhdFZtYXRhdGFRYV8QJDRCNzUzQzkwLUI2OTQtNDc5Mi04NkFCLTFFMzlDRjgyODkwOdMtLhMvMDFXTlMua2V5c1pOUy5vYmplY3RzoKCACNIzNDU2WiRjbGFzc25hbWVYJGNsYXNzZXNcTlNEaWN0aW9uYXJ5ojc4XE5TRGljdGlvbmFyeVhOU09iamVjdNIuEzo7oIAK0jM0PT5XTlNBcnJheaI9OFl3b25kZXJmdWzSMzRBQldDb250YWN0o0FDOFhNVExNb2RlbAAIABEAGgAkACkAMgA3AEkATABRAFMAYQBnAIIAlACeAKcAwQDKAN8A5gD7ARIBGwEiATwBRQFHAUkBSwFNAU8BUQFTAVUBVwFZAVsBXQFfAWEBZgFtAW8BlgGdAaUBsAGxAbIBtAG5AcQBzQHaAd0B6gHzAfgB+QH7AgACCAILAhUCGgIiAiYAAAAAAAACAQAAAAAAAABEAAAAAAAAAAAAAAAAAAACLw==","recordType":30,"uniqueId":"793CABBC-ACA5-43AC-99A2-BCA18A0E4483","multipleAccountLabelText":"boop"}"#.utf8)
        ),
        (
            SignalAccount(
                recipientPhoneNumber: "little",
                recipientServiceId: nil, // Was hardcoded to a non-ServiceId string
                multipleAccountLabelText: "a",
                cnContactId: nil,
                givenName: "matata",
                familyName: "what",
                nickname: "a",
                fullName: "wonderful",
                contactAvatarHash: Data(base64Encoded: "mary")
            ),
            Data(#"{"recipientPhoneNumber":"little","contactAvatarHash":"mary","recipientUUID":"lamb","contact":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGtCwwnKCkqKywyOTw\/QFUkbnVsbN0NDg8QERITFBUWFxgZGhscHR4fICEhIyEdHV8QD01UTE1vZGVsVmVyc2lvbllmaXJzdE5hbWVYbGFzdE5hbWVfEBdjb21wYXJhYmxlTmFtZUxhc3RGaXJzdFh1bmlxdWVJZF8QEnBob25lTnVtYmVyTmFtZU1hcFYkY2xhc3NfEBJwYXJzZWRQaG9uZU51bWJlcnNfEBR1c2VyVGV4dFBob25lTnVtYmVyc1hmdWxsTmFtZVZlbWFpbHNfEBdjb21wYXJhYmxlTmFtZUZpcnN0TGFzdFhuaWNrbmFtZYACgASAA4AFgAaAB4AMgAmACYALgAmABYAFEABUd2hhdFZtYXRhdGFRYV8QJDkyQTk2ODc2LTQ4QzMtNDlGMi1BOTFGLUNFRDU0ODE5RDIzRNMtLhMvMDFXTlMua2V5c1pOUy5vYmplY3RzoKCACNIzNDU2WiRjbGFzc25hbWVYJGNsYXNzZXNcTlNEaWN0aW9uYXJ5ojc4XE5TRGljdGlvbmFyeVhOU09iamVjdNIuEzo7oIAK0jM0PT5XTlNBcnJheaI9OFl3b25kZXJmdWzSMzRBQldDb250YWN0o0FDOFhNVExNb2RlbAAIABEAGgAkACkAMgA3AEkATABRAFMAYQBnAIIAlACeAKcAwQDKAN8A5gD7ARIBGwEiATwBRQFHAUkBSwFNAU8BUQFTAVUBVwFZAVsBXQFfAWEBZgFtAW8BlgGdAaUBsAGxAbIBtAG5AcQBzQHaAd0B6gHzAfgB+QH7AgACCAILAhUCGgIiAiYAAAAAAAACAQAAAAAAAABEAAAAAAAAAAAAAAAAAAACLw==","recordType":30,"uniqueId":"80BCC511-FA30-4A74-AD09-00E7EA09FE4F","multipleAccountLabelText":"a"}"#.utf8)
        ),
        (
            SignalAccount(
                recipientPhoneNumber: "white as",
                recipientServiceId: nil, // Was hardcoded to a non-ServiceId string
                multipleAccountLabelText: "was",
                cnContactId: nil,
                givenName: "ain't",
                familyName: "no",
                nickname: "passing",
                fullName: "phrase",
                contactAvatarHash: nil
            ),
            Data(#"{"recordType":30,"recipientUUID":"snow","recipientPhoneNumber":"white as","uniqueId":"A7BCB477-240D-40BD-A23E-BC361C9CBBDB","multipleAccountLabelText":"was","contact":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGtCwwnKCkqKywyOTw\/QFUkbnVsbN0NDg8QERITFBUWFxgZGhscHR4fICEhIyEdHV8QD01UTE1vZGVsVmVyc2lvbllmaXJzdE5hbWVYbGFzdE5hbWVfEBdjb21wYXJhYmxlTmFtZUxhc3RGaXJzdFh1bmlxdWVJZF8QEnBob25lTnVtYmVyTmFtZU1hcFYkY2xhc3NfEBJwYXJzZWRQaG9uZU51bWJlcnNfEBR1c2VyVGV4dFBob25lTnVtYmVyc1hmdWxsTmFtZVZlbWFpbHNfEBdjb21wYXJhYmxlTmFtZUZpcnN0TGFzdFhuaWNrbmFtZYACgASAA4AFgAaAB4AMgAmACYALgAmABYAFEABSbm9VYWluJ3RXcGFzc2luZ18QJDMwMzc3MTc1LTJGMTAtNERGQi05NjAwLTg5NkQyNjJDM0U5OdMtLhMvMDFXTlMua2V5c1pOUy5vYmplY3RzoKCACNIzNDU2WiRjbGFzc25hbWVYJGNsYXNzZXNcTlNEaWN0aW9uYXJ5ojc4XE5TRGljdGlvbmFyeVhOU09iamVjdNIuEzo7oIAK0jM0PT5XTlNBcnJheaI9OFZwaHJhc2XSMzRBQldDb250YWN0o0FDOFhNVExNb2RlbAAIABEAGgAkACkAMgA3AEkATABRAFMAYQBnAIIAlACeAKcAwQDKAN8A5gD7ARIBGwEiATwBRQFHAUkBSwFNAU8BUQFTAVUBVwFZAVsBXQFfAWEBZAFqAXIBmQGgAagBswG0AbUBtwG8AccB0AHdAeAB7QH2AfsB\/AH+AgMCCwIOAhUCGgIiAiYAAAAAAAACAQAAAAAAAABEAAAAAAAAAAAAAAAAAAACLw=="}"#.utf8)
        )
    ]

    /// Note: These strings were generated before migrating `SignalAccount` from
    /// codegen to `SDSCodableModel`. So we use these legacy constants to make
    /// sure that the new decoding can handle legacy data in the db.
    static let legacyConstants: [(SignalAccount, jsonData: Data)] = [
        (
            SignalAccount(
                recipientPhoneNumber: "little",
                recipientServiceId: nil, // Was hardcoded to a non-ServiceId string
                multipleAccountLabelText: "a",
                cnContactId: nil,
                givenName: "matata",
                familyName: "what",
                nickname: "a",
                fullName: "wonderful",
                contactAvatarHash: Data(base64Encoded: "mary")
            ),
            Data(#"{"recipientPhoneNumber":"little","contactAvatarHash":"mary","recipientUUID":"lamb","contact":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGtCwwnKCkqKywyOTw\/QFUkbnVsbN0NDg8QERITFBUWFxgZGhscHR4fICEhIyEdHV8QD01UTE1vZGVsVmVyc2lvbllmaXJzdE5hbWVYbGFzdE5hbWVfEBdjb21wYXJhYmxlTmFtZUxhc3RGaXJzdFh1bmlxdWVJZF8QEnBob25lTnVtYmVyTmFtZU1hcFYkY2xhc3NfEBJwYXJzZWRQaG9uZU51bWJlcnNfEBR1c2VyVGV4dFBob25lTnVtYmVyc1hmdWxsTmFtZVZlbWFpbHNfEBdjb21wYXJhYmxlTmFtZUZpcnN0TGFzdFhuaWNrbmFtZYACgASAA4AFgAaAB4AMgAmACYALgAmABYAFEABUd2hhdFZtYXRhdGFRYV8QJEI0Qjc3RTUxLTk3RjMtNDc2Ri05QTIwLUU1N0JFNTM3RUEyNdMtLhMvMDFXTlMua2V5c1pOUy5vYmplY3RzoKCACNIzNDU2WiRjbGFzc25hbWVYJGNsYXNzZXNcTlNEaWN0aW9uYXJ5ojc4XE5TRGljdGlvbmFyeVhOU09iamVjdNIuEzo7oIAK0jM0PT5XTlNBcnJheaI9OFl3b25kZXJmdWzSMzRBQldDb250YWN0o0FDOFhNVExNb2RlbAAIABEAGgAkACkAMgA3AEkATABRAFMAYQBnAIIAlACeAKcAwQDKAN8A5gD7ARIBGwEiATwBRQFHAUkBSwFNAU8BUQFTAVUBVwFZAVsBXQFfAWEBZgFtAW8BlgGdAaUBsAGxAbIBtAG5AcQBzQHaAd0B6gHzAfgB+QH7AgACCAILAhUCGgIiAiYAAAAAAAACAQAAAAAAAABEAAAAAAAAAAAAAAAAAAACLw==","recordType":30,"uniqueId":"hello","multipleAccountLabelText":"a"}"#.utf8)
        ),
        (
            SignalAccount(
                recipientPhoneNumber: "white as",
                recipientServiceId: nil, // Was hardcoded to a non-ServiceId string
                multipleAccountLabelText: "was",
                cnContactId: nil,
                givenName: "ain't",
                familyName: "no",
                nickname: "passing",
                fullName: "phrase",
                contactAvatarHash: Data(base64Encoded: "whose")
            ),
            Data(#"{"recordType":30,"recipientUUID":"snow","recipientPhoneNumber":"white as","uniqueId":"hi","multipleAccountLabelText":"was","contact":"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGtCwwnKCkqKywyOTw\/QFUkbnVsbN0NDg8QERITFBUWFxgZGhscHR4fICEhIyEdHV8QD01UTE1vZGVsVmVyc2lvbllmaXJzdE5hbWVYbGFzdE5hbWVfEBdjb21wYXJhYmxlTmFtZUxhc3RGaXJzdFh1bmlxdWVJZF8QEnBob25lTnVtYmVyTmFtZU1hcFYkY2xhc3NfEBJwYXJzZWRQaG9uZU51bWJlcnNfEBR1c2VyVGV4dFBob25lTnVtYmVyc1hmdWxsTmFtZVZlbWFpbHNfEBdjb21wYXJhYmxlTmFtZUZpcnN0TGFzdFhuaWNrbmFtZYACgASAA4AFgAaAB4AMgAmACYALgAmABYAFEABSbm9VYWluJ3RXcGFzc2luZ18QJDMwQTdCMzZCLUE2MUQtNDAxMi1BMzNCLUI3OTA4NEM1OUM4N9MtLhMvMDFXTlMua2V5c1pOUy5vYmplY3RzoKCACNIzNDU2WiRjbGFzc25hbWVYJGNsYXNzZXNcTlNEaWN0aW9uYXJ5ojc4XE5TRGljdGlvbmFyeVhOU09iamVjdNIuEzo7oIAK0jM0PT5XTlNBcnJheaI9OFZwaHJhc2XSMzRBQldDb250YWN0o0FDOFhNVExNb2RlbAAIABEAGgAkACkAMgA3AEkATABRAFMAYQBnAIIAlACeAKcAwQDKAN8A5gD7ARIBGwEiATwBRQFHAUkBSwFNAU8BUQFTAVUBVwFZAVsBXQFfAWEBZAFqAXIBmQGgAagBswG0AbUBtwG8AccB0AHdAeAB7QH2AfsB\/AH+AgMCCwIOAhUCGgIiAiYAAAAAAAACAQAAAAAAAABEAAAAAAAAAAAAAAAAAAACLw=="}"#.utf8)
        )
    ]

    func validate(against otherAccount: SignalAccount) throws {
        guard hasSameContent(otherAccount) else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
