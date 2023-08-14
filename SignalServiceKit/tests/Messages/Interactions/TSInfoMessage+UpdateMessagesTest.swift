//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class TSInfoMessageUpdateMessagesTest: XCTestCase {
    private typealias UpdateMessage = TSInfoMessage.UpdateMessage

    // MARK: - Hardcoded constant data

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
            UpdateMessage.printHardcodedJsonDataForConstants()
        case .runTest:
            for (idx, (constant, jsonData)) in UpdateMessage.constants.enumerated() {
                do {
                    let decoded = try JSONDecoder().decode(UpdateMessage.self, from: jsonData)
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
}

extension TSInfoMessage.UpdateMessage: ValidatableModel {
    static var constants: [(TSInfoMessage.UpdateMessage, base64JsonData: Data)] {
        [
            (
                .sequenceOfInviteLinkRequestAndCancels(count: 12, isTail: true),
                Data(base64Encoded: "eyJzZXF1ZW5jZU9mSW52aXRlTGlua1JlcXVlc3RBbmRDYW5jZWxzIjp7ImNvdW50IjoxMiwiaXNUYWlsIjp0cnVlfX0=")!
            ),
            (
                .sequenceOfInviteLinkRequestAndCancels(count: 0, isTail: false),
                Data(base64Encoded: "eyJzZXF1ZW5jZU9mSW52aXRlTGlua1JlcXVlc3RBbmRDYW5jZWxzIjp7ImNvdW50IjowLCJpc1RhaWwiOmZhbHNlfX0=")!
            ),
            (
                .invitedPniPromotedToFullMemberAci(
                    pni: Pni.constantForTesting("PNI:7CE80DE3-6243-4AD5-AE60-0D1F205391DA").codableUuid,
                    aci: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC").codableUuid
                ),
                Data(base64Encoded: "eyJpbnZpdGVkUG5pUHJvbW90ZWRUb0Z1bGxNZW1iZXJBY2kiOnsicG5pIjoiN0NFODBERTMtNjI0My00QUQ1LUFFNjAtMEQxRjIwNTM5MURBIiwiYWNpIjoiNTZFRTBFRjQtQTdERi00QjUyLUJGQUYtQzYzN0YxNUI0RkVDIn19")!
            )
        ]
    }

    func validate(against: TSInfoMessage.UpdateMessage) throws {
        var validated: Bool = false

        switch (self, against) {
        case let (
            .sequenceOfInviteLinkRequestAndCancels(selfCount, selfIsTail),
            .sequenceOfInviteLinkRequestAndCancels(againstCount, againstIsTail)
        ):
            if
                selfCount == againstCount,
                selfIsTail == againstIsTail
            {
                validated = true
            }
        case let (
            .invitedPniPromotedToFullMemberAci(selfPni, selfAci),
            .invitedPniPromotedToFullMemberAci(againstPni, againstAci)
        ):
            if
                selfPni == againstPni,
                selfAci == againstAci
            {
                validated = true
            }
        default:
            break
        }

        guard validated else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
