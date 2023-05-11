//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

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
                uuid: UUID(uuidString: "ec43071b-2dc0-4d82-82b2-0266968a4c2b")!,
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
                uuid: UUID(uuidString: "ec43071b-2dc0-4d82-82b2-0266968a4c2b")!,
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
                uuid: UUID(uuidString: "ec43071b-2dc0-4d82-82b2-0266968a4c2b")!,
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
                uuid: UUID(uuidString: "ec43071b-2dc0-4d82-82b2-0266968a4c2b")!,
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
                uuid: UUID(uuidString: "ec43071b-2dc0-4d82-82b2-0266968a4c2b")!,
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
            uuid: UUID(uuidString: "ec43071b-2dc0-4d82-82b2-0266968a4c2b")!,
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
