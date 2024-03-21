//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class OWSContactSerializationTest: XCTestCase {

    // MARK: - Hardcoded constant data

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedJsonDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedArchiverDataDecodes() {
        switch HardcodedDataTestMode.mode {
        case .printStrings:
            for (idx, (constant, _)) in OWSContact.constants.enumerated() {
                let serializedArchiver = try! NSKeyedArchiver.archivedData(
                    withRootObject: constant,
                    requiringSecureCoding: false
                )
                print("\(Self.self) constant \(idx) keyed archiver: \(serializedArchiver.base64EncodedString())")
            }

        case .runTest:
            for (idx, (constant, archiverData)) in OWSContact.constants.enumerated() {
                do {
                    let deserialized = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: OWSContact.self,
                        from: archiverData,
                        requiringSecureCoding: false
                    )!
                    try deserialized.validate(against: constant)
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate NSKeyedArchiver-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }
            }
        }
    }
}

extension OWSContact {
    static let constants: [(OWSContact, base64NSArchiverData: Data)] = [
        // A simple one
        (
            OWSContact(
                name: OWSContactName(givenName: "Luke", familyName: "Skywalker"),
                phoneNumbers: [],
                emails: [],
                addresses: [],
                avatarAttachmentId: nil
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGrCwwbHB0hJy4vMDVVJG51bGzXDQ4PEBESExQVFhcXFxpfEA9pc1Byb2ZpbGVBdmF0YXJWJGNsYXNzXxAPTVRMTW9kZWxWZXJzaW9uVmVtYWlsc1lhZGRyZXNzZXNccGhvbmVOdW1iZXJzVG5hbWWAA4AKgAKABIAEgASABhAACNIeDh8gWk5TLm9iamVjdHOggAXSIiMkJVokY2xhc3NuYW1lWCRjbGFzc2VzV05TQXJyYXmiJCZYTlNPYmplY3TUKCkPDiorFi1ZZ2l2ZW5OYW1lWmZhbWlseU5hbWWAB4AIgAKACVRMdWtlWVNreXdhbGtlctIiIzEyXk9XU0NvbnRhY3ROYW1lozM0Jl5PV1NDb250YWN0TmFtZVhNVExNb2RlbNIiIzY3Wk9XU0NvbnRhY3SjODQmWk9XU0NvbnRhY3QACAARABoAJAApADIANwBJAEwAUQBTAF8AZQB0AIYAjQCfAKYAsAC9AMIAxADGAMgAygDMAM4A0ADSANMA2ADjAOQA5gDrAPYA/wEHAQoBEwEcASYBMQEzATUBNwE5AT4BSAFNAVwBYAFvAXgBfQGIAYwAAAAAAAACAQAAAAAAAAA5AAAAAAAAAAAAAAAAAAABlw==")!
        ),
        // The works
        (
            OWSContact(
                name: OWSContactName(
                    givenName: "Anakin",
                    familyName: "Skywalker",
                    namePrefix: "Master",
                    nameSuffix: "But Not Granted A Seat In The Jedi Council",
                    middleName: "Sand",
                    nickname: "Darth Vader",
                    organizationName: "Sith"
                ),
                phoneNumbers: [
                    .init(type: .mobile, phoneNumber: "+15555555555"),
                    .init(type: .work, label: "Death Star Hotline", phoneNumber: "+15555555500")
                ],
                emails: [
                    .init(type: .mobile, email: "anakin@tatooine.planet"),
                    .init(type: .work, label: "Death Star Inbox", email: "vader@death.star")
                ],
                addresses: [
                    .init(
                        type: .home,
                        street: "Fortress Vader",
                        region: "Volcano",
                        country: "Mustafar"
                    ),
                    .init(
                        type: .work,
                        label: "Work",
                        street: "Death Star",
                        pobox: "0",
                        neighborhood: "Space?",
                        city: "Uh...space?",
                        region: "Also space",
                        postcode: "0",
                        country: "Spaaaaaaace"
                    )
                ],
                avatarAttachmentId: "1234"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEC8LDB0eHyAmMTIzNDU9Tk9QUVJTVFVWWV5lZmpwcXJzeH+AhIqLjJ2en6ChoqOkqFUkbnVsbNgNDg8QERITFBUWFxgZGhscXxAPaXNQcm9maWxlQXZhdGFyVmVtYWlsc18QD01UTE1vZGVsVmVyc2lvblYkY2xhc3NZYWRkcmVzc2VzXxASYXZhdGFyQXR0YWNobWVudElkXHBob25lTnVtYmVyc1RuYW1lgAOAFoACgC6ABYAEgB6AJRAACVQxMjM00iEQIiVaTlMub2JqZWN0c6IjJIAGgAyAFdYQJygPKSorLC0XLzBWcmVnaW9uVnN0cmVldFdjb3VudHJ5W2FkZHJlc3NUeXBlgAuAB4AIgAKACYAKV1ZvbGNhbm9eRm9ydHJlc3MgVmFkZXJYTXVzdGFmYXIQAdI2Nzg5WiRjbGFzc25hbWVYJGNsYXNzZXNfEBFPV1NDb250YWN0QWRkcmVzc6M6OzxfEBFPV1NDb250YWN0QWRkcmVzc1hNVExNb2RlbFhOU09iamVjdNsnKA8+KT8QQEFCKkNEF0ZHSCtKS0hNVGNpdHlYcG9zdGNvZGVcbmVpZ2hib3Job29kVWxhYmVsVXBvYm94gA2ADoACgA+AEIARgAuAEoATgBGAFFpBbHNvIHNwYWNlWkRlYXRoIFN0YXJbVWguLi5zcGFjZT9bU3BhYWFhYWFhY2VRMFZTcGFjZT9UV29yaxAC0jY3V1hXTlNBcnJheaJXPNIhEFololtcgBeAGoAV1F9gDxBhTRdkVWVtYWlsWWVtYWlsVHlwZYAYgBSAAoAZXxAWYW5ha2luQHRhdG9vaW5lLnBsYW5ldNI2N2doXxAPT1dTQ29udGFjdEVtYWlso2k7PF8QD09XU0NvbnRhY3RFbWFpbNVfQQ9gEGtsF25kgByAG4ACgB2AGV8QEERlYXRoIFN0YXIgSW5ib3hfEBB2YWRlckBkZWF0aC5zdGFyEAPSIRB0JaJ1doAfgCKAFdQQeQ96e00XfllwaG9uZVR5cGVbcGhvbmVOdW1iZXKAIYAUgAKAIFwrMTU1NTU1NTU1NTXSNjeBgl8QFU9XU0NvbnRhY3RQaG9uZU51bWJlcqODOzxfEBVPV1NDb250YWN0UGhvbmVOdW1iZXLVEEF5D3p7hm4XiYAhgCOAHYACgCRfEBJEZWF0aCBTdGFyIEhvdGxpbmVcKzE1NTU1NTU1NTAw2RAPjY6PkJGSk5QXlpeYmZqbnFhuaWNrbmFtZVptaWRkbGVOYW1lXxAQb3JnYW5pemF0aW9uTmFtZVpuYW1lU3VmZml4Wm5hbWVQcmVmaXhZZ2l2ZW5OYW1lWmZhbWlseU5hbWWALYACgCaAJ4AogCmAKoArgCxbRGFydGggVmFkZXJUU2FuZFRTaXRoXxAqQnV0IE5vdCBHcmFudGVkIEEgU2VhdCBJbiBUaGUgSmVkaSBDb3VuY2lsVk1hc3RlclZBbmFraW5ZU2t5d2Fsa2Vy0jY3paZeT1dTQ29udGFjdE5hbWWjpzs8Xk9XU0NvbnRhY3ROYW1l0jY3qapaT1dTQ29udGFjdKOrOzxaT1dTQ29udGFjdAAIABEAGgAkACkAMgA3AEkATABRAFMAhQCLAJwArgC1AMcAzgDYAO0A+gD/AQEBAwEFAQcBCQELAQ0BDwERARIBFwEcAScBKgEsAS4BMAE9AUQBSwFTAV8BYQFjAWUBZwFpAWsBcwGCAYsBjQGSAZ0BpgG6Ab4B0gHbAeQB+wIAAgkCFgIcAiICJAImAigCKgIsAi4CMAIyAjQCNgI4AkMCTgJaAmYCaAJvAnQCdgJ7AoMChgKLAo4CkAKSApQCnQKjAq0CrwKxArMCtQLOAtMC5QLpAvsDBgMIAwoDDAMOAxADIwM2AzgDPQNAA0IDRANGA08DWQNlA2cDaQNrA20DegN/A5cDmwOzA74DwAPCA8QDxgPIA90D6gP9BAYEEQQkBC8EOgREBE8EUQRTBFUEVwRZBFsEXQRfBGEEbQRyBHcEpASrBLIEvATBBNAE1ATjBOgE8wT3AAAAAAAAAgEAAAAAAAAArAAAAAAAAAAAAAAAAAAABQI=")!
        ),
    ]

    func validate(against: OWSContact) throws {
        guard
            name == against.name,
            phoneNumbers == against.phoneNumbers,
            emails == against.emails,
            addresses == against.addresses,
            legacyAvatarAttachmentId == against.legacyAvatarAttachmentId,
            isValid == against.isValid
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
