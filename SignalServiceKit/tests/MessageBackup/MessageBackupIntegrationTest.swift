//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

private extension MessageBackupIntegrationTestCase {
    var deps: DependenciesBridge { .shared }
}

// MARK: -

final class MessageBackupAccountDataTest: MessageBackupIntegrationTestCase {
    func testAccountData() async throws {
        try await runTest(backupName: "account-data") { sdsTx, tx in
            XCTAssertNotNil(profileManager.localProfileKey())

            switch deps.localUsernameManager.usernameState(tx: tx) {
            case .available(let username, let usernameLink):
                XCTAssertEqual(username, "boba_fett.66")
                XCTAssertEqual(usernameLink.handle, UUID(uuidString: "61C101A2-00D5-4217-89C2-0518D8497AF0")!)
                XCTAssertEqual(deps.localUsernameManager.usernameLinkQRCodeColor(tx: tx), .olive)
            case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
                XCTFail("Unexpected username state!")
            }

            XCTAssertEqual(profileManager.localGivenName(), "Boba")
            XCTAssertEqual(profileManager.localFamilyName(), "Fett")
            XCTAssertNil(profileManager.localProfileAvatarData())

            XCTAssertNotNil(subscriptionManager.getSubscriberID(transaction: sdsTx))
            XCTAssertEqual(subscriptionManager.getSubscriberCurrencyCode(transaction: sdsTx), "USD")
            XCTAssertTrue(subscriptionManager.userManuallyCancelledSubscription(transaction: sdsTx))

            XCTAssertTrue(receiptManager.areReadReceiptsEnabled(transaction: sdsTx))
            XCTAssertTrue(preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: sdsTx))
            XCTAssertTrue(typingIndicatorsImpl.areTypingIndicatorsEnabled())
            XCTAssertFalse(SSKPreferences.areLinkPreviewsEnabled(transaction: sdsTx))
            XCTAssertEqual(deps.phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx), .nobody)
            XCTAssertTrue(SSKPreferences.preferContactAvatars(transaction: sdsTx))
            let universalExpireConfig = deps.disappearingMessagesConfigurationStore.fetch(for: .universal, tx: tx)
            XCTAssertEqual(universalExpireConfig?.isEnabled, true)
            XCTAssertEqual(universalExpireConfig?.durationSeconds, 3600)
            XCTAssertEqual(ReactionManager.customEmojiSet(transaction: sdsTx), ["🏎️"])
            XCTAssertTrue(subscriptionManager.displayBadgesOnProfile(transaction: sdsTx))
            XCTAssertTrue(SSKPreferences.shouldKeepMutedChatsArchived(transaction: sdsTx))
            XCTAssertTrue(StoryManager.hasSetMyStoriesPrivacy(transaction: sdsTx))
            XCTAssertTrue(systemStoryManager.isOnboardingStoryRead(transaction: sdsTx))
            XCTAssertFalse(StoryManager.areStoriesEnabled(transaction: sdsTx))
            XCTAssertTrue(StoryManager.areViewReceiptsEnabled(transaction: sdsTx))
            XCTAssertTrue(systemStoryManager.isOnboardingOverlayViewed(transaction: sdsTx))
            XCTAssertFalse(deps.usernameEducationManager.shouldShowUsernameEducation(tx: tx))
            XCTAssertEqual(udManager.phoneNumberSharingMode(tx: tx), .nobody)
        }
    }
}

// MARK: -

final class MessageBackupContactTest: MessageBackupIntegrationTestCase {
    private let aciFixture = Aci.constantForTesting("4076995E-0531-4042-A9E4-1E67A77DF358")
    private let pniFixture = Pni.constantForTesting("PNI:26FC02A2-BA58-4A7D-B081-9DA23971570A")

    private func assert(
        recipient: SignalRecipient,
        username: String = "han_solo.44",
        phoneNumber: String = "+17735550199",
        isBlocked: Bool,
        isHidden: Bool,
        isRegistered: Bool,
        unregisteredAtTimestamp: UInt64?,
        isWhitelisted: Bool,
        givenName: String = "Han",
        familyName: String = "Solo",
        isStoryHidden: Bool = true,
        sdsTx: SDSAnyReadTransaction,
        tx: DBReadTransaction
    ) {
        XCTAssertEqual(recipient.aci, aciFixture)
        XCTAssertEqual(recipient.pni, pniFixture)
        XCTAssertEqual(deps.usernameLookupManager.fetchUsername(forAci: recipient.aci!, transaction: tx), username)
        XCTAssertEqual(recipient.phoneNumber?.stringValue, phoneNumber)
        XCTAssertEqual(blockingManager.isAddressBlocked(recipient.address, transaction: sdsTx), isBlocked)
        XCTAssertEqual(deps.recipientHidingManager.isHiddenRecipient(recipient, tx: tx), isHidden)
        XCTAssertEqual(recipient.isRegistered, isRegistered)
        XCTAssertEqual(recipient.unregisteredAtTimestamp, unregisteredAtTimestamp)
        let recipientProfile = profileManager.getUserProfile(for: recipient.address, transaction: sdsTx)
        XCTAssertNotNil(recipientProfile?.profileKey)
        XCTAssertEqual(profileManager.isUser(inProfileWhitelist: recipient.address, transaction: sdsTx), isWhitelisted)
        XCTAssertEqual(recipientProfile?.givenName, givenName)
        XCTAssertEqual(recipientProfile?.familyName, familyName)
        XCTAssertEqual(StoryStoreImpl().getOrCreateStoryContextAssociatedData(for: recipient.aci!, tx: tx).isHidden, isStoryHidden)
    }

    private func allRecipients(tx: any DBReadTransaction) -> [SignalRecipient] {
        var result = [SignalRecipient]()
        deps.recipientDatabaseTable.enumerateAll(tx: tx) { result.append($0) }
        return result
    }

    func testRegisteredBlockedContact() async throws {
        try await runTest(backupName: "registered-blocked-contact") { sdsTx, tx in
            let allRecipients = allRecipients(tx: tx)
            XCTAssertEqual(allRecipients.count, 1)

            assert(
                recipient: allRecipients.first!,
                isBlocked: true,
                isHidden: true,
                isRegistered: true,
                unregisteredAtTimestamp: nil,
                isWhitelisted: false,
                sdsTx: sdsTx,
                tx: tx
            )
        }
    }

    func testUnregisteredContact() async throws {
        try await runTest(backupName: "unregistered-contact") { sdsTx, tx in
            let allRecipients = allRecipients(tx: tx)
            XCTAssertEqual(allRecipients.count, 1)

            assert(
                recipient: allRecipients.first!,
                isBlocked: false,
                isHidden: false,
                isRegistered: false,
                unregisteredAtTimestamp: 1713157772000,
                isWhitelisted: true,
                sdsTx: sdsTx,
                tx: tx
            )
        }
    }
}

// MARK: -

final class MessageBackupDistributionListTest: MessageBackupIntegrationTestCase {
    typealias ListValidationBlock = ((TSPrivateStoryThread) -> Void)

    private var privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager { deps.privateStoryThreadDeletionManager }
    private var threadStore: ThreadStore { deps.threadStore }

    func testDistributionList() async throws {
        try await runTest(
            backupName: "story-distribution-list",
            dateProvider: {
                /// "Deleted distribution list" logic relies on the distance
                /// between timestamps in the Backup binary and the "current
                /// time". To keep this test stable over time, we need to
                /// hardcode the "current time"; the timestamp below is from the
                /// time this test was originally committed.
                return Date(millisecondsSince1970: 1717631700000)
            }
        ) { sdsTx, tx in
            let deletedStories = privateStoryThreadDeletionManager.allDeletedIdentifiers(tx: tx)
            XCTAssertEqual(deletedStories.count, 2)

            let validationBlocks: [UUID: ListValidationBlock] = [
                UUID(uuidString: TSPrivateStoryThread.myStoryUniqueId)!: { thread in
                    XCTAssertTrue(thread.allowsReplies)
                },
                UUID(data: Data(base64Encoded: "me/ptJ9tRnyCWu/eg9uP7Q==")!)!: { thread in
                    XCTAssertEqual(thread.name, "Mandalorians")
                    XCTAssertTrue(thread.allowsReplies)
                    XCTAssertEqual(thread.storyViewMode, .blockList)
                    XCTAssertEqual(thread.addresses.count, 2)
                },
                UUID(data: Data(base64Encoded: "ZYoHlxwxS8aBGSQJ1tL0sA==")!)!: { thread in
                    XCTAssertEqual(thread.name, "Hutts")
                    XCTAssertFalse(thread.allowsReplies)
                    // check member list
                    XCTAssertEqual(thread.storyViewMode, .explicit)
                    XCTAssertEqual(thread.addresses.count, 1)
                }
            ]

            try threadStore.enumerateStoryThreads(tx: tx) { thread in
                do {
                    let validationBlock = try XCTUnwrap(validationBlocks[UUID(uuidString: thread.uniqueId)!])
                    validationBlock(thread)
                } catch {
                    XCTFail("Missing validation block")
                }

                return true
            }
        }
    }
}

// MARK: -

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
                            .sessionSwitchover:
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
                            .reportedSpam:
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

// MARK: -

final class MessageBackupExpirationTimerChatUpdateTest: MessageBackupIntegrationTestCase {
    func testExpirationTimerChatUpdates() async throws {
        let contactAci = Aci.constantForTesting("5F8C568D-0119-47BD-81AA-BB87C9B71995")

        try await runTest(backupName: "expiration-timer-chat-update-message") { sdsTx, tx in
            let fetchedContactThreads = deps.threadStore.fetchContactThreads(serviceId: contactAci, tx: tx)
            XCTAssertEqual(fetchedContactThreads.count, 1)
            let expectedContactThread = fetchedContactThreads.first!

            struct ExpectedExpirationTimerUpdate {
                let authorIsLocalUser: Bool
                let expiresInSeconds: UInt32
                var isEnabled: Bool { expiresInSeconds > 0 }
            }

            var expectedUpdates: [ExpectedExpirationTimerUpdate] = [
                .init(authorIsLocalUser: false, expiresInSeconds: 0),
                .init(authorIsLocalUser: true, expiresInSeconds: 9001),
            ]

            try deps.interactionStore.enumerateAllInteractions(tx: tx) { interaction -> Bool in
                XCTAssertEqual(interaction.uniqueThreadId, expectedContactThread.uniqueId)

                guard let dmUpdateInfoMessage = interaction as? OWSDisappearingConfigurationUpdateInfoMessage else {
                    XCTFail("Unexpected interaction type: \(type(of: interaction))")
                    return false
                }

                guard let expectedUpdate = expectedUpdates.popFirst() else {
                    XCTFail("Unexpectedly missing expected timer change!")
                    return false
                }

                XCTAssertEqual(dmUpdateInfoMessage.configurationDurationSeconds, expectedUpdate.expiresInSeconds)
                XCTAssertEqual(dmUpdateInfoMessage.configurationIsEnabled, expectedUpdate.isEnabled)
                if expectedUpdate.authorIsLocalUser {
                    XCTAssertNil(dmUpdateInfoMessage.createdByRemoteName)
                } else {
                    XCTAssertNotNil(dmUpdateInfoMessage.createdByRemoteName)
                }

                return true
            }
        }
    }
}
