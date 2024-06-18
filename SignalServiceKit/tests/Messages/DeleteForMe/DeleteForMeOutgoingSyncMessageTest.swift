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
    ]

    func validate(against: DeleteForMeOutgoingSyncMessage.Contents) throws {
        guard
            messageDeletes == against.messageDeletes,
            conversationDeletes == against.conversationDeletes,
            localOnlyConversationDelete == against.localOnlyConversationDelete
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
