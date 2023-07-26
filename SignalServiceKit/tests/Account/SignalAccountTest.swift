//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SignalAccountTest: XCTestCase {

    // MARK: - (De)Serialization Tests

    private let inMemoryDatabase = InMemoryDatabase()

    func testRoundTrip() {
        for (idx, (constant, _)) in SignalAccount.constants.enumerated() {
            inMemoryDatabase.insert(record: constant)

            guard let deserialized = inMemoryDatabase.fetchExactlyOne(modelType: SignalAccount.self) else {
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

            inMemoryDatabase.remove(model: deserialized)
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

    func testKeyedArchiverRoundTrip() throws {
        let aliceAci = "00000000-0000-4000-8000-000000000000"
        let alicePhoneNumber = "+16505550100"
        let aliceAddress = SignalServiceAddress(
            serviceId: FutureAci.constantForTesting(aliceAci),
            phoneNumber: nil,
            cache: SignalServiceAddressCache(),
            cachePolicy: .ignoreCache
        )
        let aliceContact = Contact(
            address: aliceAddress,
            phoneNumberLabel: "Mobile",
            givenName: "Alice",
            familyName: "Aliceson",
            nickname: nil,
            fullName: "Alice Aliceson"
        )
        let aliceAccount = SignalAccount(
            contact: aliceContact,
            contactAvatarHash: nil,
            multipleAccountLabelText: "Mobile",
            recipientPhoneNumber: alicePhoneNumber,
            recipientUUID: aliceAci
        )

        let encodedData = try NSKeyedArchiver.archivedData(withRootObject: aliceAccount, requiringSecureCoding: false)
        let decodedAccount = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: SignalAccount.self, from: encodedData, requiringSecureCoding: false
        ))

        XCTAssertEqual(decodedAccount.uniqueId, aliceAccount.uniqueId)
        XCTAssertEqual(decodedAccount.recipientUUID, aliceAccount.recipientUUID)
        XCTAssertEqual(decodedAccount.recipientPhoneNumber, aliceAccount.recipientPhoneNumber)
        XCTAssertEqual(decodedAccount.multipleAccountLabelText, aliceAccount.multipleAccountLabelText)
        XCTAssertEqual(decodedAccount.contact?.fullName, aliceAccount.contact?.fullName)
    }

    /// Taken from cc83e60eda, just prior to `accountSchemaVersion` == 1.
    func testHardcodedKeyedArchiverLegacyDataVersion0() throws {
        let encodedData = try XCTUnwrap(Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGISJYJHZlcnNpb25YJG9iamVjdHNZJGFyY2hpdmVyVCR0b3ASAAGGoKcHCBUWFxgZVSRudWxs1gkKCwwNDg8QERITFFtyZWNpcGllbnRJZFYkY2xhc3NfEBloYXNNdWx0aXBsZUFjY291bnRDb250YWN0WHVuaXF1ZUlkXxAPTVRMTW9kZWxWZXJzaW9uXxAYbXVsdGlwbGVBY2NvdW50TGFiZWxUZXh0gAOABoAEgAOAAoAFEABcKzE2NTA1NTUwMTAwCVZNb2JpbGXSGhscHVgkY2xhc3Nlc1okY2xhc3NuYW1lpB0eHyBdU2lnbmFsQWNjb3VudF8QE1RTWWFwRGF0YWJhc2VPYmplY3RYTVRMTW9kZWxYTlNPYmplY3RfEA9OU0tleWVkQXJjaGl2ZXLRIyRUcm9vdIABAAgAEQAaACMALQAyADcAPwBFAFIAXgBlAIEAigCcALcAuQC7AL0AvwDBAMMAxQDSANMA2gDfAOgA8wD4AQYBHAElAS4BQAFDAUgAAAAAAAACAQAAAAAAAAAlAAAAAAAAAAAAAAAAAAABSg=="))
        let signalAccount = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: SignalAccount.self, from: encodedData, requiringSecureCoding: false
        ))
        XCTAssertEqual(signalAccount.uniqueId, "+16505550100")
        XCTAssertEqual(signalAccount.recipientPhoneNumber, "+16505550100")
        XCTAssertEqual(signalAccount.multipleAccountLabelText, "Mobile")
    }

    /// Taken from 50b410ca57, just prior to the `SDSCodableModel` migration.
    func testHardcodedKeyedArchiverLegacyDataVersion1() throws {
        let encodedData = try XCTUnwrap(Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvECELDB8gISIjJDs8PT4/R0hJUFRabG1ub3N3en5/gIOEiIlVJG51bGzZDQ4PEBESExQVFhcYGRobHB0eVmdyZGJJZF8QFHJlY2lwaWVudFBob25lTnVtYmVyXxAPTVRMTW9kZWxWZXJzaW9uViRjbGFzc11yZWNpcGllbnRVVUlEXxAUYWNjb3VudFNjaGVtYVZlcnNpb25XY29udGFjdF8QGG11bHRpcGxlQWNjb3VudExhYmVsVGV4dFh1bmlxdWVJZIADgASAAoAggAWABoAHgA6AHxAAEHtcKzE2NTA1NTUwMTAwXxAkMDAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwQUFBEAHcDyUmJygpECorLC0uGDAxMjM0NTY3ODk6WWZpcnN0TmFtZVhsYXN0TmFtZV8QF2NvbXBhcmFibGVOYW1lTGFzdEZpcnN0WHVuaXF1ZUlkXxAScGhvbmVOdW1iZXJOYW1lTWFwXxAScGFyc2VkUGhvbmVOdW1iZXJzXxAUdXNlclRleHRQaG9uZU51bWJlcnNYZnVsbE5hbWVWZW1haWxzXxAXY29tcGFyYWJsZU5hbWVGaXJzdExhc3SAAoAJgAiACoALgAyAHoAQgBmAG4AcgB1YQWxpY2Vzb25VQWxpY2VeQWxpY2Vzb24JQWxpY2VfECQwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDBCQkLTQEEQQkRGV05TLmtleXNaTlMub2JqZWN0c6FDgA2hHYAOgA9cKzE2NTA1NTUwMTAwVk1vYmlsZdJKS0xNWiRjbGFzc25hbWVYJGNsYXNzZXNcTlNEaWN0aW9uYXJ5ok5PXE5TRGljdGlvbmFyeVhOU09iamVjdNJBEFFToVKAEYAY01UQVkNYWV8QIVJQRGVmYXVsdHNLZXlQaG9uZU51bWJlckNhbm9uaWNhbF8QHlJQRGVmYXVsdHNLZXlQaG9uZU51bWJlclN0cmluZ4ANgBeAEtkQW1xdXl9gYWJjZGVmZBtkamRfEBFjb3VudHJ5Q29kZVNvdXJjZV8QEml0YWxpYW5MZWFkaW5nWmVyb15uYXRpb25hbE51bWJlcl8QHHByZWZlcnJlZERvbWVzdGljQ2FycmllckNvZGVbY291bnRyeUNvZGVZZXh0ZW5zaW9uXxAUbnVtYmVyT2ZMZWFkaW5nWmVyb3NYcmF3SW5wdXSAFoAAgBSAE4AAgAaAAIAVgAATAAAAAYPC0RQIEAHSSktwcV1OQlBob25lTnVtYmVyonJPXU5CUGhvbmVOdW1iZXLSSkt0dVtQaG9uZU51bWJlcqJ2T1tQaG9uZU51bWJlctJKS3h5V05TQXJyYXmieE/SQRB7U6F8gBqAGFwrMTY1MDU1NTAxMDBeQWxpY2UgQWxpY2Vzb27SQRCBU6CAGF5BbGljZQlBbGljZXNvbtJKS4WGV0NvbnRhY3SjhYdPWE1UTE1vZGVsXxAkMDAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwQ0ND0kpLiotdU2lnbmFsQWNjb3VudKWMjY6HT11TaWduYWxBY2NvdW50WUJhc2VNb2RlbF8QE1RTWWFwRGF0YWJhc2VPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAHcAfQCQAJcArgDAAMcA1QDsAPQBDwEYARoBHAEeASABIgEkASYBKAEqASwBLgE7AWIBZAF9AYcBkAGqAbMByAHdAfQB/QIEAh4CIAIiAiQCJgIoAioCLAIuAjACMgI0AjYCPwJFAlQCewKCAooClQKXApkCmwKdAp8CrAKzArgCwwLMAtkC3ALpAvIC9wL5AvsC/QMEAygDSQNLA00DTwNiA3YDiwOaA7kDxQPPA+YD7wPxA/MD9QP3A/kD+wP9A/8EAQQKBAsEDQQSBCAEIwQxBDYEQgRFBFEEVgReBGEEZgRoBGoEbAR5BIgEjQSOBJAEnwSkBKwEsAS5BOAE5QTzBPkFBwURAAAAAAAAAgEAAAAAAAAAjwAAAAAAAAAAAAAAAAAABSc="))
        let signalAccount = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: SignalAccount.self, from: encodedData, requiringSecureCoding: false
        ))
        XCTAssertEqual(signalAccount.grdbId, 123)
        XCTAssertEqual(signalAccount.uniqueId, "00000000-0000-4000-8000-000000000CCC")
        XCTAssertEqual(signalAccount.recipientUUID, "00000000-0000-4000-8000-000000000AAA")
        XCTAssertEqual(signalAccount.recipientPhoneNumber, "+16505550100")
        XCTAssertEqual(signalAccount.multipleAccountLabelText, "Mobile")
        XCTAssertNotNil(signalAccount.contact?.uniqueId, "00000000-0000-4000-8000-000000000BBB")
    }

    // MARK: - Display Name Tests

    private var userDefaults = TestUtils.userDefaults()

    func testPreferredDisplayName() {
        guard let signalAccount = SignalAccount.constants.first?.0 else {
            XCTFail("Cannot find mock SignalAccount")
            return
        }

        userDefaults.setNicknamePreferred(isPreferred: false)

        XCTAssert(signalAccount.contactFirstName == "matata")
        XCTAssert(signalAccount.contactLastName == "what")
        // `signalAccount` does have a nickname on it, but because user defaults indicate
        // it is not preferred, we don't have it here.
        XCTAssert(signalAccount.contactNicknameIfAvailable(userDefaults: self.userDefaults) == nil)
        XCTAssert(signalAccount.contactPreferredDisplayName(userDefaults: self.userDefaults) == "matata what")

        var expectedNameComponents = PersonNameComponents()
        expectedNameComponents.givenName = "matata"
        expectedNameComponents.familyName = "what"
        XCTAssert(signalAccount.contactPersonNameComponents(userDefaults: self.userDefaults) == expectedNameComponents)
    }

    func testNicknamePreferred() {
        let contact = Contact(
            address: SignalServiceAddress(
                serviceId: FutureAci.constantForTesting("ec43071b-2dc0-4d82-82b2-0266968a4c2b"),
                phoneNumber: "myPhoneNumber",
                cache: SignalServiceAddressCache(),
                cachePolicy: .ignoreCache
            ),
            phoneNumberLabel: "hakuna",
            givenName: "matata",
            familyName: "what",
            // white space should be stripped because string processed for display
            nickname: "a ",
            fullName: "wonderful"
        )
        let signalAccount = SignalAccount.buildMock(contact: contact)

        userDefaults.setNicknamePreferred(isPreferred: true)

        XCTAssert(signalAccount.contactFirstName == "matata")
        XCTAssert(signalAccount.contactLastName == "what")
        XCTAssert(signalAccount.contactNicknameIfAvailable(userDefaults: self.userDefaults) == "a")
        XCTAssert(signalAccount.contactPreferredDisplayName(userDefaults: self.userDefaults) == "a")

        var expectedNameComponents = PersonNameComponents()
        expectedNameComponents.givenName = "matata"
        expectedNameComponents.familyName = "what"
        expectedNameComponents.nickname = "a"
        XCTAssert(signalAccount.contactPersonNameComponents(userDefaults: self.userDefaults) == expectedNameComponents)
    }

    func testEmptyNickname() {
        let contact = Contact(
            address: SignalServiceAddress(
                serviceId: FutureAci.constantForTesting("ec43071b-2dc0-4d82-82b2-0266968a4c2b"),
                phoneNumber: "myPhoneNumber",
                cache: SignalServiceAddressCache(),
                cachePolicy: .ignoreCache
            ),
            phoneNumberLabel: "hakuna",
            givenName: " matata",
            familyName: " what",
            nickname: "",
            fullName: "wonderful"
        )
        let signalAccount = SignalAccount.buildMock(contact: contact)

        userDefaults.setNicknamePreferred(isPreferred: true)

        // test stripping white space; litmus test for having called `.displayStringIfNonEmpty`
        XCTAssert(signalAccount.contactFirstName == "matata")
        XCTAssert(signalAccount.contactLastName == "what")

        XCTAssert(signalAccount.contactNicknameIfAvailable(userDefaults: self.userDefaults) == nil)
        XCTAssert(signalAccount.contactPreferredDisplayName(userDefaults: self.userDefaults) == "matata what")

        var expectedNameComponents = PersonNameComponents()
        expectedNameComponents.givenName = "matata"
        expectedNameComponents.familyName = "what"
        XCTAssert(signalAccount.contactPersonNameComponents(userDefaults: self.userDefaults) == expectedNameComponents)
    }

    func testNilNickname() {
        let contact = Contact(
            address: SignalServiceAddress(
                serviceId: FutureAci.constantForTesting("ec43071b-2dc0-4d82-82b2-0266968a4c2b"),
                phoneNumber: "myPhoneNumber",
                cache: SignalServiceAddressCache(),
                cachePolicy: .ignoreCache
            ),
            phoneNumberLabel: "hakuna",
            givenName: "matata",
            familyName: "what",
            nickname: nil,
            fullName: "wonderful"
        )
        let signalAccount = SignalAccount.buildMock(contact: contact)

        userDefaults.setNicknamePreferred(isPreferred: true)

        XCTAssert(signalAccount.contactNicknameIfAvailable(userDefaults: self.userDefaults) == nil)
        XCTAssert(signalAccount.contactPreferredDisplayName(userDefaults: self.userDefaults) == "matata what")

        var expectedNameComponents = PersonNameComponents()
        expectedNameComponents.givenName = "matata"
        expectedNameComponents.familyName = "what"
        XCTAssert(signalAccount.contactPersonNameComponents(userDefaults: self.userDefaults) == expectedNameComponents)
    }

    func testFullNameOnly() {
        let contact = Contact(
            address: SignalServiceAddress(
                serviceId: FutureAci.constantForTesting("ec43071b-2dc0-4d82-82b2-0266968a4c2b"),
                phoneNumber: "myPhoneNumber",
                cache: SignalServiceAddressCache(),
                cachePolicy: .ignoreCache
            ),
            phoneNumberLabel: "hakuna",
            givenName: "",
            familyName: "",
            nickname: nil,
            // string should end up processed such that white space stripped
            fullName: "wonderful "
        )
        let signalAccount = SignalAccount.buildMock(contact: contact)

        XCTAssert(signalAccount.contactFirstName == nil)
        XCTAssert(signalAccount.contactLastName == nil)
        XCTAssert(signalAccount.contactPreferredDisplayName(userDefaults: self.userDefaults) == "wonderful")

        var expectedNameComponents = PersonNameComponents()
        expectedNameComponents.givenName = "wonderful"
        XCTAssert(signalAccount.contactPersonNameComponents(userDefaults: self.userDefaults) == expectedNameComponents)
    }

    func testNoNames() {
        let contact = Contact(
            address: SignalServiceAddress(
                serviceId: FutureAci.constantForTesting("ec43071b-2dc0-4d82-82b2-0266968a4c2b"),
                phoneNumber: "myPhoneNumber",
                cache: SignalServiceAddressCache(),
                cachePolicy: .ignoreCache
            ),
            phoneNumberLabel: "hakuna",
            givenName: "",
            familyName: "",
            nickname: nil,
            fullName: ""
        )
        let signalAccount = SignalAccount.buildMock(contact: contact)

        XCTAssert(signalAccount.contactFirstName == nil)
        XCTAssert(signalAccount.contactLastName == nil)
        XCTAssert(signalAccount.contactPreferredDisplayName(userDefaults: self.userDefaults) == nil)
        XCTAssert(signalAccount.contactPersonNameComponents(userDefaults: self.userDefaults) == nil)
    }
}

extension SignalAccount: ValidatableModel {
    static let constants: [(SignalAccount, base64JsonData: Data)] = [
        (
            SignalAccount(
                contact: ContactFixtures.contactA,
                contactAvatarHash: Data(base64Encoded: "mary"),
                multipleAccountLabelText: "a",
                recipientPhoneNumber: "little",
                recipientUUID: "lamb"
            ),
            Data(base64Encoded: "eyJyZWNpcGllbnRQaG9uZU51bWJlciI6ImxpdHRsZSIsImNvbnRhY3RBdmF0YXJIYXNoIjoibWFyeSIsInJlY2lwaWVudFVVSUQiOiJsYW1iIiwiY29udGFjdCI6IlluQnNhWE4wTUREVUFRSURCQVVHQndwWUpIWmxjbk5wYjI1WkpHRnlZMmhwZG1WeVZDUjBiM0JZSkc5aWFtVmpkSE1TQUFHR29GOFFEMDVUUzJWNVpXUkJjbU5vYVhabGN0RUlDVlJ5YjI5MGdBR3RDd3duS0NrcUt5d3lPVHdcL1FGVWtiblZzYk4wTkRnOFFFUklURkJVV0Z4Z1pHaHNjSFI0ZklDRWhJeUVkSFY4UUQwMVVURTF2WkdWc1ZtVnljMmx2YmxsbWFYSnpkRTVoYldWWWJHRnpkRTVoYldWZkVCZGpiMjF3WVhKaFlteGxUbUZ0WlV4aGMzUkdhWEp6ZEZoMWJtbHhkV1ZKWkY4UUVuQm9iMjVsVG5WdFltVnlUbUZ0WlUxaGNGWWtZMnhoYzNOZkVCSndZWEp6WldSUWFHOXVaVTUxYldKbGNuTmZFQlIxYzJWeVZHVjRkRkJvYjI1bFRuVnRZbVZ5YzFobWRXeHNUbUZ0WlZabGJXRnBiSE5mRUJkamIyMXdZWEpoWW14bFRtRnRaVVpwY25OMFRHRnpkRmh1YVdOcmJtRnRaWUFDZ0FTQUE0QUZnQWFBQjRBTWdBbUFDWUFMZ0FtQUJZQUZFQUJVZDJoaGRGWnRZWFJoZEdGUllWOFFKRGt5UVRrMk9EYzJMVFE0UXpNdE5EbEdNaTFCT1RGR0xVTkZSRFUwT0RFNVJESXpSTk10TGhNdk1ERlhUbE11YTJWNWMxcE9VeTV2WW1wbFkzUnpvS0NBQ05Jek5EVTJXaVJqYkdGemMyNWhiV1ZZSkdOc1lYTnpaWE5jVGxORWFXTjBhVzl1WVhKNW9qYzRYRTVUUkdsamRHbHZibUZ5ZVZoT1UwOWlhbVZqZE5JdUV6bzdvSUFLMGpNMFBUNVhUbE5CY25KaGVhSTlPRmwzYjI1a1pYSm1kV3pTTXpSQlFsZERiMjUwWVdOMG8wRkRPRmhOVkV4TmIyUmxiQUFJQUJFQUdnQWtBQ2tBTWdBM0FFa0FUQUJSQUZNQVlRQm5BSUlBbEFDZUFLY0F3UURLQU44QTVnRDdBUklCR3dFaUFUd0JSUUZIQVVrQlN3Rk5BVThCVVFGVEFWVUJWd0ZaQVZzQlhRRmZBV0VCWmdGdEFXOEJsZ0dkQWFVQnNBR3hBYklCdEFHNUFjUUJ6UUhhQWQwQjZnSHpBZmdCK1FIN0FnQUNDQUlMQWhVQ0dnSWlBaVlBQUFBQUFBQUNBUUFBQUFBQUFBQkVBQUFBQUFBQUFBQUFBQUFBQUFBQ0x3PT0iLCJyZWNvcmRUeXBlIjozMCwidW5pcXVlSWQiOiI4MEJDQzUxMS1GQTMwLTRBNzQtQUQwOS0wMEU3RUEwOUZFNEYiLCJtdWx0aXBsZUFjY291bnRMYWJlbFRleHQiOiJhIn0=")!
        ),
        (
            SignalAccount(
                contact: ContactFixtures.contactB,
                contactAvatarHash: Data(base64Encoded: "whose"),
                multipleAccountLabelText: "was",
                recipientPhoneNumber: "white as",
                recipientUUID: "snow"
            ),
            Data(base64Encoded: "eyJyZWNvcmRUeXBlIjozMCwicmVjaXBpZW50VVVJRCI6InNub3ciLCJyZWNpcGllbnRQaG9uZU51bWJlciI6IndoaXRlIGFzIiwidW5pcXVlSWQiOiJBN0JDQjQ3Ny0yNDBELTQwQkQtQTIzRS1CQzM2MUM5Q0JCREIiLCJtdWx0aXBsZUFjY291bnRMYWJlbFRleHQiOiJ3YXMiLCJjb250YWN0IjoiWW5Cc2FYTjBNRERVQVFJREJBVUdCd3BZSkhabGNuTnBiMjVaSkdGeVkyaHBkbVZ5VkNSMGIzQllKRzlpYW1WamRITVNBQUdHb0Y4UUQwNVRTMlY1WldSQmNtTm9hWFpsY3RFSUNWUnliMjkwZ0FHdEN3d25LQ2txS3l3eU9Ud1wvUUZVa2JuVnNiTjBORGc4UUVSSVRGQlVXRnhnWkdoc2NIUjRmSUNFaEl5RWRIVjhRRDAxVVRFMXZaR1ZzVm1WeWMybHZibGxtYVhKemRFNWhiV1ZZYkdGemRFNWhiV1ZmRUJkamIyMXdZWEpoWW14bFRtRnRaVXhoYzNSR2FYSnpkRmgxYm1seGRXVkpaRjhRRW5Cb2IyNWxUblZ0WW1WeVRtRnRaVTFoY0ZZa1kyeGhjM05mRUJKd1lYSnpaV1JRYUc5dVpVNTFiV0psY25OZkVCUjFjMlZ5VkdWNGRGQm9iMjVsVG5WdFltVnljMWhtZFd4c1RtRnRaVlpsYldGcGJITmZFQmRqYjIxd1lYSmhZbXhsVG1GdFpVWnBjbk4wVEdGemRGaHVhV05yYm1GdFpZQUNnQVNBQTRBRmdBYUFCNEFNZ0FtQUNZQUxnQW1BQllBRkVBQlNibTlWWVdsdUozUlhjR0Z6YzJsdVoxOFFKRE13TXpjM01UYzFMVEpHTVRBdE5FUkdRaTA1TmpBd0xUZzVOa1F5TmpKRE0wVTVPZE10TGhNdk1ERlhUbE11YTJWNWMxcE9VeTV2WW1wbFkzUnpvS0NBQ05Jek5EVTJXaVJqYkdGemMyNWhiV1ZZSkdOc1lYTnpaWE5jVGxORWFXTjBhVzl1WVhKNW9qYzRYRTVUUkdsamRHbHZibUZ5ZVZoT1UwOWlhbVZqZE5JdUV6bzdvSUFLMGpNMFBUNVhUbE5CY25KaGVhSTlPRlp3YUhKaGMyWFNNelJCUWxkRGIyNTBZV04wbzBGRE9GaE5WRXhOYjJSbGJBQUlBQkVBR2dBa0FDa0FNZ0EzQUVrQVRBQlJBRk1BWVFCbkFJSUFsQUNlQUtjQXdRREtBTjhBNWdEN0FSSUJHd0VpQVR3QlJRRkhBVWtCU3dGTkFVOEJVUUZUQVZVQlZ3RlpBVnNCWFFGZkFXRUJaQUZxQVhJQm1RR2dBYWdCc3dHMEFiVUJ0d0c4QWNjQjBBSGRBZUFCN1FIMkFmc0JcL0FIK0FnTUNDd0lPQWhVQ0dnSWlBaVlBQUFBQUFBQUNBUUFBQUFBQUFBQkVBQUFBQUFBQUFBQUFBQUFBQUFBQ0x3PT0ifQ==")!
        )
    ]

    /// Note: These base64-encoded strings were generated before migrating
    /// `SignalAccount` from codegen to `SDSCodableModel`. So we use these
    /// legacy constants to make sure that the new decoding can handle
    /// legacy data in the db.
    static let legacyConstants: [(SignalAccount, base64JsonData: Data)] = [
        (
            SignalAccount(
                contact: ContactFixtures.contactA,
                contactAvatarHash: Data(base64Encoded: "mary"),
                multipleAccountLabelText: "a",
                recipientPhoneNumber: "little",
                recipientUUID: "lamb"
            ),
            Data(base64Encoded: "eyJyZWNpcGllbnRQaG9uZU51bWJlciI6ImxpdHRsZSIsImNvbnRhY3RBdmF0YXJIYXNoIjoibWFyeSIsInJlY2lwaWVudFVVSUQiOiJsYW1iIiwiY29udGFjdCI6IlluQnNhWE4wTUREVUFRSURCQVVHQndwWUpIWmxjbk5wYjI1WkpHRnlZMmhwZG1WeVZDUjBiM0JZSkc5aWFtVmpkSE1TQUFHR29GOFFEMDVUUzJWNVpXUkJjbU5vYVhabGN0RUlDVlJ5YjI5MGdBR3RDd3duS0NrcUt5d3lPVHdcL1FGVWtiblZzYk4wTkRnOFFFUklURkJVV0Z4Z1pHaHNjSFI0ZklDRWhJeUVkSFY4UUQwMVVURTF2WkdWc1ZtVnljMmx2YmxsbWFYSnpkRTVoYldWWWJHRnpkRTVoYldWZkVCZGpiMjF3WVhKaFlteGxUbUZ0WlV4aGMzUkdhWEp6ZEZoMWJtbHhkV1ZKWkY4UUVuQm9iMjVsVG5WdFltVnlUbUZ0WlUxaGNGWWtZMnhoYzNOZkVCSndZWEp6WldSUWFHOXVaVTUxYldKbGNuTmZFQlIxYzJWeVZHVjRkRkJvYjI1bFRuVnRZbVZ5YzFobWRXeHNUbUZ0WlZabGJXRnBiSE5mRUJkamIyMXdZWEpoWW14bFRtRnRaVVpwY25OMFRHRnpkRmh1YVdOcmJtRnRaWUFDZ0FTQUE0QUZnQWFBQjRBTWdBbUFDWUFMZ0FtQUJZQUZFQUJVZDJoaGRGWnRZWFJoZEdGUllWOFFKRUkwUWpjM1JUVXhMVGszUmpNdE5EYzJSaTA1UVRJd0xVVTFOMEpGTlRNM1JVRXlOZE10TGhNdk1ERlhUbE11YTJWNWMxcE9VeTV2WW1wbFkzUnpvS0NBQ05Jek5EVTJXaVJqYkdGemMyNWhiV1ZZSkdOc1lYTnpaWE5jVGxORWFXTjBhVzl1WVhKNW9qYzRYRTVUUkdsamRHbHZibUZ5ZVZoT1UwOWlhbVZqZE5JdUV6bzdvSUFLMGpNMFBUNVhUbE5CY25KaGVhSTlPRmwzYjI1a1pYSm1kV3pTTXpSQlFsZERiMjUwWVdOMG8wRkRPRmhOVkV4TmIyUmxiQUFJQUJFQUdnQWtBQ2tBTWdBM0FFa0FUQUJSQUZNQVlRQm5BSUlBbEFDZUFLY0F3UURLQU44QTVnRDdBUklCR3dFaUFUd0JSUUZIQVVrQlN3Rk5BVThCVVFGVEFWVUJWd0ZaQVZzQlhRRmZBV0VCWmdGdEFXOEJsZ0dkQWFVQnNBR3hBYklCdEFHNUFjUUJ6UUhhQWQwQjZnSHpBZmdCK1FIN0FnQUNDQUlMQWhVQ0dnSWlBaVlBQUFBQUFBQUNBUUFBQUFBQUFBQkVBQUFBQUFBQUFBQUFBQUFBQUFBQ0x3PT0iLCJyZWNvcmRUeXBlIjozMCwidW5pcXVlSWQiOiJoZWxsbyIsIm11bHRpcGxlQWNjb3VudExhYmVsVGV4dCI6ImEifQ==")!
        ),
        (
            SignalAccount(
                contact: ContactFixtures.contactB,
                contactAvatarHash: Data(base64Encoded: "whose"),
                multipleAccountLabelText: "was",
                recipientPhoneNumber: "white as",
                recipientUUID: "snow"
            ),
            Data(base64Encoded: "eyJyZWNvcmRUeXBlIjozMCwicmVjaXBpZW50VVVJRCI6InNub3ciLCJyZWNpcGllbnRQaG9uZU51bWJlciI6IndoaXRlIGFzIiwidW5pcXVlSWQiOiJoaSIsIm11bHRpcGxlQWNjb3VudExhYmVsVGV4dCI6IndhcyIsImNvbnRhY3QiOiJZbkJzYVhOME1ERFVBUUlEQkFVR0J3cFlKSFpsY25OcGIyNVpKR0Z5WTJocGRtVnlWQ1IwYjNCWUpHOWlhbVZqZEhNU0FBR0dvRjhRRDA1VFMyVjVaV1JCY21Ob2FYWmxjdEVJQ1ZSeWIyOTBnQUd0Q3d3bktDa3FLeXd5T1R3XC9RRlVrYm5Wc2JOME5EZzhRRVJJVEZCVVdGeGdaR2hzY0hSNGZJQ0VoSXlFZEhWOFFEMDFVVEUxdlpHVnNWbVZ5YzJsdmJsbG1hWEp6ZEU1aGJXVlliR0Z6ZEU1aGJXVmZFQmRqYjIxd1lYSmhZbXhsVG1GdFpVeGhjM1JHYVhKemRGaDFibWx4ZFdWSlpGOFFFbkJvYjI1bFRuVnRZbVZ5VG1GdFpVMWhjRllrWTJ4aGMzTmZFQkp3WVhKelpXUlFhRzl1WlU1MWJXSmxjbk5mRUJSMWMyVnlWR1Y0ZEZCb2IyNWxUblZ0WW1WeWMxaG1kV3hzVG1GdFpWWmxiV0ZwYkhOZkVCZGpiMjF3WVhKaFlteGxUbUZ0WlVacGNuTjBUR0Z6ZEZodWFXTnJibUZ0WllBQ2dBU0FBNEFGZ0FhQUI0QU1nQW1BQ1lBTGdBbUFCWUFGRUFCU2JtOVZZV2x1SjNSWGNHRnpjMmx1WjE4UUpETXdRVGRDTXpaQ0xVRTJNVVF0TkRBeE1pMUJNek5DTFVJM09UQTRORU0xT1VNNE45TXRMaE12TURGWFRsTXVhMlY1YzFwT1V5NXZZbXBsWTNSem9LQ0FDTkl6TkRVMldpUmpiR0Z6YzI1aGJXVllKR05zWVhOelpYTmNUbE5FYVdOMGFXOXVZWEo1b2pjNFhFNVRSR2xqZEdsdmJtRnllVmhPVTA5aWFtVmpkTkl1RXpvN29JQUswak0wUFQ1WFRsTkJjbkpoZWFJOU9GWndhSEpoYzJYU016UkJRbGREYjI1MFlXTjBvMEZET0ZoTlZFeE5iMlJsYkFBSUFCRUFHZ0FrQUNrQU1nQTNBRWtBVEFCUkFGTUFZUUJuQUlJQWxBQ2VBS2NBd1FES0FOOEE1Z0Q3QVJJQkd3RWlBVHdCUlFGSEFVa0JTd0ZOQVU4QlVRRlRBVlVCVndGWkFWc0JYUUZmQVdFQlpBRnFBWElCbVFHZ0FhZ0Jzd0cwQWJVQnR3RzhBY2NCMEFIZEFlQUI3UUgyQWZzQlwvQUgrQWdNQ0N3SU9BaFVDR2dJaUFpWUFBQUFBQUFBQ0FRQUFBQUFBQUFCRUFBQUFBQUFBQUFBQUFBQUFBQUFDTHc9PSJ9")!
        )
    ]

    private enum ContactFixtures {
        private static let address = SignalServiceAddress(
            serviceId: FutureAci.constantForTesting("ec43071b-2dc0-4d82-82b2-0266968a4c2b"),
            phoneNumber: "myPhoneNumber",
            cache: SignalServiceAddressCache(),
            cachePolicy: .ignoreCache
        )
        static let contactA = Contact(
            address: address,
            phoneNumberLabel: "hakuna",
            givenName: "matata",
            familyName: "what",
            nickname: "a",
            fullName: "wonderful"
        )
        static let contactB = Contact(
            address: address,
            phoneNumberLabel: "phrase",
            givenName: "ain't",
            familyName: "no",
            nickname: "passing",
            fullName: "phrase"
        )
    }

    func validate(against: SignalAccount) throws {
        guard
            contactsAreEqual(contact, against.contact),
            contactAvatarHash == against.contactAvatarHash,
            multipleAccountLabelText == against.multipleAccountLabelText,
            recipientPhoneNumber == against.recipientPhoneNumber,
            recipientUUID == against.recipientUUID
        else {
            throw ValidatableModelError.failedToValidate
        }
    }

    private func contactsAreEqual(_ contactA: Contact?, _ contactB: Contact?) -> Bool {
        guard let contactA = contactA, let contactB = contactB else {
            return contactA == contactB
        }
        return contactA.hasSameContent(contactB)
    }

    fileprivate static func buildMock(contact: Contact) -> SignalAccount {
        return SignalAccount(
            contact: contact,
            contactAvatarHash: Data(base64Encoded: "mary"),
            multipleAccountLabelText: "a",
            recipientPhoneNumber: "little",
            recipientUUID: "lamb"
        )
    }
}
