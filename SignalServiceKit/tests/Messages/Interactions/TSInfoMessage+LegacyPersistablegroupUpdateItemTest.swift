//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class TSInfoMessageLegacyPersistableGroupUpdateItemTest: XCTestCase {
    private typealias UpdateItem = TSInfoMessage.LegacyPersistableGroupUpdateItem

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

    func testConvertToNewUpdateItem() throws {
        let updaterAci = Aci.randomForTesting()

        for (constant, _) in UpdateItem.constants {
            let expectedNewValue: TSInfoMessage.PersistableGroupUpdateItem
            switch constant {
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail):
                expectedNewValue = .sequenceOfInviteLinkRequestAndCancels(
                    requester: updaterAci.codableUuid,
                    count: count,
                    isTail: isTail
                )
            case let .inviteRemoved(_, wasLocalUser):
                if wasLocalUser {
                    expectedNewValue = .localUserInviteRevoked(
                        revokerAci: updaterAci.codableUuid
                    )
                } else {
                    expectedNewValue = .unnamedUserInvitesWereRevokedByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        count: 1
                    )
                }
            case let .invitedPniPromotedToFullMemberAci(_, aci):
                expectedNewValue = .invitedPniPromotedToFullMemberAci(
                    newMember: aci,
                    inviter: nil
                )
            }
            guard let newValue = constant.toNewItem(
                updater: .aci(updaterAci),
                oldGroupModel: nil,
                localIdentifiers: .init(
                    aci: .randomForTesting(),
                    pni: Pni.constantForTesting("PNI:7CE80DE3-6243-4AD5-AE60-0D1F205391DA"),
                    e164: .init("+15555555555")!
                )
            ) else {
                XCTFail("Should always be able to convert!")
                return
            }

            try newValue.validate(against: expectedNewValue)
        }
    }
}

extension TSInfoMessage.LegacyPersistableGroupUpdateItem: ValidatableModel {
    static var constants: [(TSInfoMessage.LegacyPersistableGroupUpdateItem, jsonData: Data)] {
        [
            (
                .sequenceOfInviteLinkRequestAndCancels(count: 12, isTail: true),
                Data(#"{"sequenceOfInviteLinkRequestAndCancels":{"count":12,"isTail":true}}"#.utf8)
            ),
            (
                .sequenceOfInviteLinkRequestAndCancels(count: 0, isTail: false),
                Data(#"{"sequenceOfInviteLinkRequestAndCancels":{"count":0,"isTail":false}}"#.utf8)
            ),
            (
                .invitedPniPromotedToFullMemberAci(
                    pni: Pni.constantForTesting("PNI:7CE80DE3-6243-4AD5-AE60-0D1F205391DA").codableUuid,
                    aci: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC").codableUuid
                ),
                Data(#"{"invitedPniPromotedToFullMemberAci":{"pni":"7CE80DE3-6243-4AD5-AE60-0D1F205391DA","aci":"56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC"}}"#.utf8)
            ),
            (
                .inviteRemoved(
                    invitee: Aci.constantForTesting("56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC").codableUppercaseString,
                    wasLocalUser: false
                ),
                Data(#"{"inviteRemoved":{"invitee":"56EE0EF4-A7DF-4B52-BFAF-C637F15B4FEC","wasLocalUser":false}}"#.utf8)
            ),
            (
                .inviteRemoved(
                    invitee: Pni.constantForTesting("PNI:7CE80DE3-6243-4AD5-AE60-0D1F205391DA").codableUppercaseString,
                    wasLocalUser: true
                ),
                Data(#"{"inviteRemoved":{"wasLocalUser":true,"invitee":"PNI:7CE80DE3-6243-4AD5-AE60-0D1F205391DA"}}"#.utf8)
            ),
        ]
    }

    func validate(against: TSInfoMessage.LegacyPersistableGroupUpdateItem) throws {
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
        case let (
            .inviteRemoved(selfInvitee, selfWasLocalUser),
            .inviteRemoved(againstInvitee, againstWasLocalUser)
        ):
            if
                selfInvitee == againstInvitee,
                selfWasLocalUser == againstWasLocalUser
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
