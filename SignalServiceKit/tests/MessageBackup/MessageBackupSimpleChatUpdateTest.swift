//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupSimpleChatUpdateTest: MessageBackupIntegrationTestCase {
    private struct FailTestError: Error {
        init(_ message: String) { XCTFail("Test failed! \(message)") }
    }

    private var interactionStore: any InteractionStore { deps.interactionStore }
    private var threadStore: any ThreadStore { deps.threadStore }

    private func insertAndAssert<T: Hashable>(_ element: T?, into set: inout Set<T>) throws {
        guard let element else {
            throw FailTestError("Element was nil!")
        }
        let (inserted, _) = set.insert(element)
        guard inserted else {
            throw FailTestError("Multiple elements: \(element).")
        }
    }

    func testSimpleChatUpdates() async throws {
        let expectedAci = Aci.constantForTesting("5F8C568D-0119-47BD-81AA-BB87C9B71995")

        try await runTest(backupName: "simple-chat-update-message") { sdsTx, tx in
            var seenVerificationStates = Set<OWSVerificationState>()
            var seenUnknownProtocolVersionAuthors = Set<Aci>()
            var seenPaymentsActivationRequestInfos = Set<TSInfoMessage.PaymentsInfoMessageAuthor>()
            var seenPaymentsActivatedInfos = Set<TSInfoMessage.PaymentsInfoMessageAuthor>()
            var seenInfoMessageTypes = Set<TSInfoMessageType>()
            var seenErrorMessageTypes = Set<TSErrorMessageType>()

            /// We should only have one thread, and it should be the one all the
            /// expected interactions belong to.
            try threadStore.enumerateNonStoryThreads(tx: tx) { thread throws -> Bool in
                guard
                    let contactThread = thread as? TSContactThread,
                    let contactAci = contactThread.contactAddress.aci
                else {
                    throw FailTestError("Unexpectedly found non-contact thread, or contact thread missing ACI!")
                }

                XCTAssertEqual(contactAci, expectedAci)
                return true
            }

            /// We should have only exactly the info/error messages we expect.
            try deps.interactionStore.enumerateAllInteractions(tx: tx) { interaction throws -> Bool in
                guard
                    let contactThread = threadStore.fetchThreadForInteraction(interaction, tx: tx) as? TSContactThread,
                    contactThread.contactAddress.aci == expectedAci
                else {
                    throw FailTestError("Info message in unexpected thread!")
                }

                if let verificationStateChange = interaction as? OWSVerificationStateChangeMessage {
                    /// Info messages for verification state changes are all
                    /// this subclass, rather than a generic info message.
                    owsPrecondition(verificationStateChange.messageType == .verificationStateChange)

                    XCTAssertTrue(verificationStateChange.isLocalChange)
                    XCTAssertEqual(verificationStateChange.recipientAddress.aci, expectedAci)
                    try insertAndAssert(
                        verificationStateChange.verificationState,
                        into: &seenVerificationStates
                    )
                } else if let unknownProtocolVersion = interaction as? OWSUnknownProtocolVersionMessage {
                    /// Info messages for unknown protocol versions are all this
                    /// subclass, rather than a generic info message.
                    owsPrecondition(unknownProtocolVersion.messageType == .unknownProtocolVersion)

                    XCTAssertTrue(unknownProtocolVersion.isProtocolVersionUnknown)
                    try insertAndAssert(
                        unknownProtocolVersion.sender?.aci! ?? localIdentifiers.aci,
                        into: &seenUnknownProtocolVersionAuthors
                    )
                } else if let infoMessage = interaction as? TSInfoMessage {
                    XCTAssertNil(infoMessage.customMessage)
                    XCTAssertNil(infoMessage.unregisteredAddress)

                    switch infoMessage.messageType {
                    case
                            .userNotRegistered,
                            .typeUnsupportedMessage,
                            .typeGroupQuit,
                            .addToContactsOffer,
                            .addUserToProfileWhitelistOffer,
                            .addGroupToProfileWhitelistOffer:
                        throw FailTestError("Unexpectedly found deprecated info message type \(infoMessage.messageType).")
                    case
                            .typeGroupUpdate,
                            .typeDisappearingMessagesUpdate,
                            .profileUpdate,
                            .threadMerge,
                            .sessionSwitchover,
                            .learnedProfileName:
                        throw FailTestError("Unexpectedly found complex update message \(infoMessage.messageType).")
                    case .verificationStateChange, .unknownProtocolVersion:
                        throw FailTestError("Unexpected message type for specific subclass in generic TSInfoMessage.")
                    case
                            .syncedThread,
                            .recipientHidden:
                        throw FailTestError("Unexpected local-only update message.")
                    case .paymentsActivationRequest:
                        try insertAndAssert(
                            infoMessage.paymentsActivationRequestAuthor(localIdentifiers: localIdentifiers),
                            into: &seenPaymentsActivationRequestInfos
                        )
                    case .paymentsActivated:
                        try insertAndAssert(
                            infoMessage.paymentsActivatedAuthor(localIdentifiers: localIdentifiers),
                            into: &seenPaymentsActivatedInfos
                        )
                    case
                            .typeSessionDidEnd,
                            .userJoinedSignal,
                            .reportedSpam,
                            .blockedOtherUser,
                            .blockedGroup,
                            .unblockedOtherUser,
                            .unblockedGroup:
                        XCTAssertNil(infoMessage.infoMessageUserInfo)
                        fallthrough
                    case .phoneNumberChange:
                        try insertAndAssert(
                            infoMessage.messageType,
                            into: &seenInfoMessageTypes
                        )
                    }
                } else if let errorMessage = interaction as? TSErrorMessage {
                    switch errorMessage.errorType {
                    case
                            .noSession,
                            .wrongTrustedIdentityKey,
                            .invalidKeyException,
                            .missingKeyId,
                            .invalidMessage,
                            .duplicateMessage,
                            .invalidVersion,
                            .unknownContactBlockOffer,
                            .groupCreationFailed:
                        throw FailTestError("Unexpectedly found deprecated error message type \(errorMessage.errorType).")
                    case .nonBlockingIdentityChange:
                        XCTAssertEqual(
                            errorMessage.recipientAddress?.aci,
                            expectedAci
                        )
                    case .sessionRefresh:
                        break
                    case .decryptionFailure:
                        XCTAssertEqual(
                            errorMessage.sender?.aci,
                            expectedAci
                        )
                    }

                    try insertAndAssert(
                        errorMessage.errorType,
                        into: &seenErrorMessageTypes
                    )
                } else {
                    throw FailTestError("Interaction was \(type(of: interaction)), not an info message.")
                }

                return true
            }

            XCTAssertEqual(
                seenVerificationStates,
                [.default, .verified],
                "Unexpected set of verification states from identity change updates: \(seenVerificationStates)."
            )
            XCTAssertEqual(
                seenUnknownProtocolVersionAuthors,
                [localIdentifiers.aci, expectedAci]
            )
            XCTAssertEqual(
                seenPaymentsActivationRequestInfos,
                [.localUser, .otherUser(expectedAci)]
            )
            XCTAssertEqual(
                seenPaymentsActivatedInfos,
                [.localUser, .otherUser(expectedAci)]
            )
            XCTAssertEqual(
                seenInfoMessageTypes.count,
                4,
                "Unexpected number of info messages: \(seenInfoMessageTypes.count)."
            )
            XCTAssertEqual(
                seenErrorMessageTypes.count,
                3,
                "Unexpected number of error messages: \(seenErrorMessageTypes.count)."
            )
        }
    }
}
