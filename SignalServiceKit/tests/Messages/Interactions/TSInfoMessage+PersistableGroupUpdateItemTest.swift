//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class TSInfoMessagePersistableGroupUpdateItemTest: XCTestCase {
    private typealias UpdateItem = TSInfoMessage.PersistableGroupUpdateItem

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
            UpdateItem.printHardcodedJsonDataForConstants()
        case .runTest:
            for (idx, (constant, jsonData)) in UpdateItem.constants.enumerated() {
                do {
                    let decoded = try JSONDecoder().decode(UpdateItem.self, from: jsonData)
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

extension TSInfoMessage.PersistableGroupUpdateItem: ValidatableModel {
    static var constants: [(TSInfoMessage.PersistableGroupUpdateItem, jsonData: Data)] {
        [
            (
                .sequenceOfInviteLinkRequestAndCancels(
                    requester: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC").codableUuid,
                    count: 12,
                    isTail: true
                ),
                Data(#"{"sequenceOfInviteLinkRequestAndCancels":{"count":12,"isTail":true,"requester":"56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC"}}"#.utf8)
            ),
            (
                .sequenceOfInviteLinkRequestAndCancels(
                    requester: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC").codableUuid,
                    count: 0,
                    isTail: false),
                Data(#"{"sequenceOfInviteLinkRequestAndCancels":{"isTail":false,"count":0,"requester":"56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC"}}"#.utf8)
            ),
            (
                .invitedPniPromotedToFullMemberAci(
                    newMember: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC").codableUuid,
                    inviter: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B5FEE").codableUuid

                ),
                Data(#"{"invitedPniPromotedToFullMemberAci":{"newMember":"56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC","inviter":"56EE0EF4-A7DF-4B52-BFAF-C637F15B5FEE"}}"#.utf8)
            )
        ]
    }

    func validate(against: TSInfoMessage.PersistableGroupUpdateItem) throws {
        var validated: Bool = false

        switch (self, against) {
        case let (
            .sequenceOfInviteLinkRequestAndCancels(selfRequester, selfCount, selfIsTail),
            .sequenceOfInviteLinkRequestAndCancels(againstRequester, againstCount, againstIsTail)
        ):
            if
                selfRequester == againstRequester,
                selfCount == againstCount,
                selfIsTail == againstIsTail
            {
                validated = true
            }
        case let (
            .invitedPniPromotedToFullMemberAci(selfNewMemberAci, selfInviter),
            .invitedPniPromotedToFullMemberAci(againstNewMemberAci, againstInviter)
        ):
            if
                selfNewMemberAci == againstNewMemberAci,
                selfInviter == againstInviter
            {
                validated = true
            }
        case let (
            .localUserInviteRevoked(selfRevokerAci),
            .localUserInviteRevoked(againstRevokerAci)
        ):
            if selfRevokerAci == againstRevokerAci {
                validated = true
            }
        case let (
            .unnamedUserInvitesWereRevokedByOtherUser(selfUpdaterAci, selfCount),
            .unnamedUserInvitesWereRevokedByOtherUser(againstUpdaterAci, againstCount)
        ):
            if
                selfUpdaterAci == againstUpdaterAci,
                selfCount == againstCount
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
