//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeleteForMeOutgoingSyncMessageTest: XCTestCase {
    private typealias Contents = DeleteForMeOutgoingSyncMessage.Contents
    private typealias Outgoing = DeleteForMeSyncMessage.Outgoing

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
            Contents.printHardcodedJsonDataForConstants()
        case .runTest:
            for (idx, (constant, jsonData)) in Contents.constants.enumerated() {
                do {
                    let decoded = try JSONDecoder().decode(Contents.self, from: jsonData)
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

extension DeleteForMeOutgoingSyncMessage.Contents: ValidatableModel {
    typealias Outgoing = DeleteForMeSyncMessage.Outgoing

    static let constants: [(DeleteForMeOutgoingSyncMessage.Contents, jsonData: Data)] = [
        (
            DeleteForMeOutgoingSyncMessage.Contents(
                messageDeletes: [
                    Outgoing.MessageDeletes(
                        conversationIdentifier: .threadE164(e164: "+17735550199"),
                        addressableMessages: [.forTests(author: .aci(aci: "4C3B579D-C6E0-42C3-AEF3-E9B9801D9271"), sentTimestamp: 1234)]
                    )
                ],
                nilAttachmentDeletes: (),
                conversationDeletes: [
                    Outgoing.ConversationDelete(
                        conversationIdentifier: .threadServiceId(serviceId: "7A8709AA-B1CA-40B8-89C2-35330E88F2A9"),
                        mostRecentAddressableMessages: [.forTests(author: .e164(e164: "+17735550198"), sentTimestamp: 5678)],
                        nilNonExpiringAddressableMessages: (),
                        isFullDelete: true
                    )
                ],
                localOnlyConversationDelete: [
                    Outgoing.LocalOnlyConversationDelete(
                        conversationIdentifier: .threadGroupId(groupId: Data(repeating: 4, count: 32))
                    )
                ]
            ),
            Data(#"{"messageDeletes":[{"addressableMessages":[{"author":{"aci":{"aci":"4C3B579D-C6E0-42C3-AEF3-E9B9801D9271"}},"sentTimestamp":1234}],"conversationIdentifier":{"threadE164":{"e164":"+17735550199"}}}],"localOnlyConversationDelete":[{"conversationIdentifier":{"threadGroupId":{"groupId":"BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ="}}}],"conversationDeletes":[{"conversationIdentifier":{"threadServiceId":{"serviceId":"7A8709AA-B1CA-40B8-89C2-35330E88F2A9"}},"mostRecentAddressableMessages":[{"author":{"e164":{"e164":"+17735550198"}},"sentTimestamp":5678}],"isFullDelete":true}]}"#.utf8)
        ),
        (
            DeleteForMeOutgoingSyncMessage.Contents(
                messageDeletes: [
                    Outgoing.MessageDeletes(
                        conversationIdentifier: .threadE164(e164: "+17735550199"),
                        addressableMessages: [.forTests(author: .aci(aci: "4C3B579D-C6E0-42C3-AEF3-E9B9801D9271"), sentTimestamp: 1234)]
                    )
                ],
                attachmentDeletes: [
                    Outgoing.AttachmentDelete(
                        conversationIdentifier: .threadServiceId(serviceId: "D8626C3E-79BB-4665-B7D6-66884F543164"),
                        targetMessage: .forTests(author: .aci(aci: "BF1C5C1B-15DA-4A49-92C7-EFBA8BFFDF4B"), sentTimestamp: 9001),
                        clientUuid: UUID(uuidString: "C374CDB9-2440-4E39-8FE5-29CD4CB5C812")!,
                        encryptedDigest: Data(repeating: 24, count: 95),
                        plaintextHash: Data(repeating: 21, count: 92)
                    )
                ],
                conversationDeletes: [
                    Outgoing.ConversationDelete(
                        conversationIdentifier: .threadServiceId(serviceId: "7A8709AA-B1CA-40B8-89C2-35330E88F2A9"),
                        mostRecentAddressableMessages: [.forTests(author: .e164(e164: "+17735550198"), sentTimestamp: 5678)],
                        nilNonExpiringAddressableMessages: (),
                        isFullDelete: true
                    )
                ],
                localOnlyConversationDelete: [
                    Outgoing.LocalOnlyConversationDelete(
                        conversationIdentifier: .threadGroupId(groupId: Data(repeating: 4, count: 32))
                    )
                ]
            ),
            Data(#"{"messageDeletes":[{"addressableMessages":[{"author":{"aci":{"aci":"4C3B579D-C6E0-42C3-AEF3-E9B9801D9271"}},"sentTimestamp":1234}],"conversationIdentifier":{"threadE164":{"e164":"+17735550199"}}}],"conversationDeletes":[{"conversationIdentifier":{"threadServiceId":{"serviceId":"7A8709AA-B1CA-40B8-89C2-35330E88F2A9"}},"mostRecentAddressableMessages":[{"author":{"e164":{"e164":"+17735550198"}},"sentTimestamp":5678}],"isFullDelete":true}],"localOnlyConversationDelete":[{"conversationIdentifier":{"threadGroupId":{"groupId":"BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ="}}}],"attachmentDeletes":[{"clientUuid":"C374CDB9-2440-4E39-8FE5-29CD4CB5C812","plaintextHash":"FRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRU=","encryptedDigest":"GBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBg=","conversationIdentifier":{"threadServiceId":{"serviceId":"D8626C3E-79BB-4665-B7D6-66884F543164"}},"targetMessage":{"author":{"aci":{"aci":"BF1C5C1B-15DA-4A49-92C7-EFBA8BFFDF4B"}},"sentTimestamp":9001}}]}"#.utf8)
        ),
        (
            DeleteForMeOutgoingSyncMessage.Contents(
                messageDeletes: [
                    Outgoing.MessageDeletes(
                        conversationIdentifier: .threadE164(e164: "+17735550199"),
                        addressableMessages: [.forTests(author: .aci(aci: "4C3B579D-C6E0-42C3-AEF3-E9B9801D9271"), sentTimestamp: 1234)]
                    )
                ],
                attachmentDeletes: [
                    Outgoing.AttachmentDelete(
                        conversationIdentifier: .threadServiceId(serviceId: "D8626C3E-79BB-4665-B7D6-66884F543164"),
                        targetMessage: .forTests(author: .aci(aci: "BF1C5C1B-15DA-4A49-92C7-EFBA8BFFDF4B"), sentTimestamp: 9001),
                        clientUuid: UUID(uuidString: "C374CDB9-2440-4E39-8FE5-29CD4CB5C812")!,
                        encryptedDigest: Data(repeating: 24, count: 95),
                        plaintextHash: Data(repeating: 21, count: 92)
                    )
                ],
                conversationDeletes: [
                    Outgoing.ConversationDelete(
                        conversationIdentifier: .threadServiceId(serviceId: "7A8709AA-B1CA-40B8-89C2-35330E88F2A9"),
                        mostRecentAddressableMessages: [.forTests(author: .e164(e164: "+17735550198"), sentTimestamp: 5678)],
                        mostRecentNonExpiringAddressableMessages: [.forTests(author: .e164(e164: "+17735550197"), sentTimestamp: 1337)],
                        isFullDelete: true
                    )
                ],
                localOnlyConversationDelete: [
                    Outgoing.LocalOnlyConversationDelete(
                        conversationIdentifier: .threadGroupId(groupId: Data(repeating: 4, count: 32))
                    )
                ]
            ),
            Data(#"{"messageDeletes":[{"addressableMessages":[{"author":{"aci":{"aci":"4C3B579D-C6E0-42C3-AEF3-E9B9801D9271"}},"sentTimestamp":1234}],"conversationIdentifier":{"threadE164":{"e164":"+17735550199"}}}],"localOnlyConversationDelete":[{"conversationIdentifier":{"threadGroupId":{"groupId":"BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ="}}}],"attachmentDeletes":[{"plaintextHash":"FRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRU=","targetMessage":{"author":{"aci":{"aci":"BF1C5C1B-15DA-4A49-92C7-EFBA8BFFDF4B"}},"sentTimestamp":9001},"encryptedDigest":"GBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBg=","conversationIdentifier":{"threadServiceId":{"serviceId":"D8626C3E-79BB-4665-B7D6-66884F543164"}},"clientUuid":"C374CDB9-2440-4E39-8FE5-29CD4CB5C812"}],"conversationDeletes":[{"mostRecentNonExpiringAddressableMessages":[{"author":{"e164":{"e164":"+17735550197"}},"sentTimestamp":1337}],"conversationIdentifier":{"threadServiceId":{"serviceId":"7A8709AA-B1CA-40B8-89C2-35330E88F2A9"}},"mostRecentAddressableMessages":[{"sentTimestamp":5678,"author":{"e164":{"e164":"+17735550198"}}}],"isFullDelete":true}]}"#.utf8)
        ),
    ]

    func validate(against: DeleteForMeOutgoingSyncMessage.Contents) throws {
        guard
            messageDeletes == against.messageDeletes,
            attachmentDeletes == against.attachmentDeletes,
            conversationDeletes == against.conversationDeletes,
            localOnlyConversationDelete == against.localOnlyConversationDelete
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
