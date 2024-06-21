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

    static let constants: [(DeleteForMeOutgoingSyncMessage.Contents, base64JsonData: Data)] = [
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
                        isFullDelete: true
                    )
                ],
                localOnlyConversationDelete: [
                    Outgoing.LocalOnlyConversationDelete(
                        conversationIdentifier: .threadGroupId(groupId: Data(repeating: 4, count: 32))
                    )
                ]
            ),
            Data(base64Encoded: "eyJtZXNzYWdlRGVsZXRlcyI6W3siYWRkcmVzc2FibGVNZXNzYWdlcyI6W3siYXV0aG9yIjp7ImFjaSI6eyJhY2kiOiI0QzNCNTc5RC1DNkUwLTQyQzMtQUVGMy1FOUI5ODAxRDkyNzEifX0sInNlbnRUaW1lc3RhbXAiOjEyMzR9XSwiY29udmVyc2F0aW9uSWRlbnRpZmllciI6eyJ0aHJlYWRFMTY0Ijp7ImUxNjQiOiIrMTc3MzU1NTAxOTkifX19XSwibG9jYWxPbmx5Q29udmVyc2F0aW9uRGVsZXRlIjpbeyJjb252ZXJzYXRpb25JZGVudGlmaWVyIjp7InRocmVhZEdyb3VwSWQiOnsiZ3JvdXBJZCI6IkJBUUVCQVFFQkFRRUJBUUVCQVFFQkFRRUJBUUVCQVFFQkFRRUJBUUVCQVE9In19fV0sImNvbnZlcnNhdGlvbkRlbGV0ZXMiOlt7ImNvbnZlcnNhdGlvbklkZW50aWZpZXIiOnsidGhyZWFkU2VydmljZUlkIjp7InNlcnZpY2VJZCI6IjdBODcwOUFBLUIxQ0EtNDBCOC04OUMyLTM1MzMwRTg4RjJBOSJ9fSwibW9zdFJlY2VudEFkZHJlc3NhYmxlTWVzc2FnZXMiOlt7ImF1dGhvciI6eyJlMTY0Ijp7ImUxNjQiOiIrMTc3MzU1NTAxOTgifX0sInNlbnRUaW1lc3RhbXAiOjU2Nzh9XSwiaXNGdWxsRGVsZXRlIjp0cnVlfV19")!
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
                        isFullDelete: true
                    )
                ],
                localOnlyConversationDelete: [
                    Outgoing.LocalOnlyConversationDelete(
                        conversationIdentifier: .threadGroupId(groupId: Data(repeating: 4, count: 32))
                    )
                ]
            ),
            Data(base64Encoded: "eyJtZXNzYWdlRGVsZXRlcyI6W3siYWRkcmVzc2FibGVNZXNzYWdlcyI6W3siYXV0aG9yIjp7ImFjaSI6eyJhY2kiOiI0QzNCNTc5RC1DNkUwLTQyQzMtQUVGMy1FOUI5ODAxRDkyNzEifX0sInNlbnRUaW1lc3RhbXAiOjEyMzR9XSwiY29udmVyc2F0aW9uSWRlbnRpZmllciI6eyJ0aHJlYWRFMTY0Ijp7ImUxNjQiOiIrMTc3MzU1NTAxOTkifX19XSwiY29udmVyc2F0aW9uRGVsZXRlcyI6W3siY29udmVyc2F0aW9uSWRlbnRpZmllciI6eyJ0aHJlYWRTZXJ2aWNlSWQiOnsic2VydmljZUlkIjoiN0E4NzA5QUEtQjFDQS00MEI4LTg5QzItMzUzMzBFODhGMkE5In19LCJtb3N0UmVjZW50QWRkcmVzc2FibGVNZXNzYWdlcyI6W3siYXV0aG9yIjp7ImUxNjQiOnsiZTE2NCI6IisxNzczNTU1MDE5OCJ9fSwic2VudFRpbWVzdGFtcCI6NTY3OH1dLCJpc0Z1bGxEZWxldGUiOnRydWV9XSwibG9jYWxPbmx5Q29udmVyc2F0aW9uRGVsZXRlIjpbeyJjb252ZXJzYXRpb25JZGVudGlmaWVyIjp7InRocmVhZEdyb3VwSWQiOnsiZ3JvdXBJZCI6IkJBUUVCQVFFQkFRRUJBUUVCQVFFQkFRRUJBUUVCQVFFQkFRRUJBUUVCQVE9In19fV0sImF0dGFjaG1lbnREZWxldGVzIjpbeyJjbGllbnRVdWlkIjoiQzM3NENEQjktMjQ0MC00RTM5LThGRTUtMjlDRDRDQjVDODEyIiwicGxhaW50ZXh0SGFzaCI6IkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVVZGUlVWRlJVVkZSVT0iLCJlbmNyeXB0ZWREaWdlc3QiOiJHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnWUdCZ1lHQmdZR0JnPSIsImNvbnZlcnNhdGlvbklkZW50aWZpZXIiOnsidGhyZWFkU2VydmljZUlkIjp7InNlcnZpY2VJZCI6IkQ4NjI2QzNFLTc5QkItNDY2NS1CN0Q2LTY2ODg0RjU0MzE2NCJ9fSwidGFyZ2V0TWVzc2FnZSI6eyJhdXRob3IiOnsiYWNpIjp7ImFjaSI6IkJGMUM1QzFCLTE1REEtNEE0OS05MkM3LUVGQkE4QkZGREY0QiJ9fSwic2VudFRpbWVzdGFtcCI6OTAwMX19XX0=")!
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
