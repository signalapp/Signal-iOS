//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

private extension MessageBackupIntegrationTestCase {
    var depBridge: DependenciesBridge { .shared }
}

final class MessageBackupAccountDataTest: MessageBackupIntegrationTestCase {
    func testAccountData() async throws {
        try await runTest(backupName: "account-data") { sdsTx, tx in
            XCTAssertNotNil(profileManager.localProfileKey())

            switch depBridge.localUsernameManager.usernameState(tx: tx) {
            case .available(let username, let usernameLink):
                XCTAssertEqual(username, "boba_fett.66")
                XCTAssertEqual(usernameLink.handle, UUID("61C101A2-00D5-4217-89C2-0518D8497AF0"))
                XCTAssertEqual(depBridge.localUsernameManager.usernameLinkQRCodeColor(tx: tx), .olive)
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
            XCTAssertEqual(depBridge.phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx), .nobody)
            XCTAssertTrue(SSKPreferences.preferContactAvatars(transaction: sdsTx))
            let universalExpireConfig = depBridge.disappearingMessagesConfigurationStore.fetch(for: .universal, tx: tx)
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
            XCTAssertFalse(depBridge.usernameEducationManager.shouldShowUsernameEducation(tx: tx))
            XCTAssertEqual(udManager.phoneNumberSharingMode(tx: tx), .nobody)
        }
    }
}

final class MessageBackupContactTest: MessageBackupIntegrationTestCase {
    private func assert(
        recipient: SignalRecipient,
        aci: Aci = .fixture,
        pni: Pni = .fixture,
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
        XCTAssertEqual(recipient.aci, aci)
        XCTAssertEqual(recipient.pni, pni)
        XCTAssertEqual(depBridge.usernameLookupManager.fetchUsername(forAci: recipient.aci!, transaction: tx), username)
        XCTAssertEqual(recipient.phoneNumber?.stringValue, phoneNumber)
        XCTAssertEqual(blockingManager.isAddressBlocked(recipient.address, transaction: sdsTx), isBlocked)
        XCTAssertEqual(depBridge.recipientHidingManager.isHiddenRecipient(recipient, tx: tx), isHidden)
        XCTAssertEqual(recipient.isRegistered, isRegistered)
        XCTAssertEqual(recipient.unregisteredAtTimestamp, unregisteredAtTimestamp)
        let recipientProfile = profileManager.getUserProfile(for: recipient.address, transaction: sdsTx)
        XCTAssertNotNil(recipientProfile?.profileKey)
        XCTAssertEqual(profileManager.isUser(inProfileWhitelist: recipient.address, transaction: sdsTx), isWhitelisted)
        XCTAssertEqual(recipientProfile?.givenName, givenName)
        XCTAssertEqual(recipientProfile?.familyName, familyName)
        XCTAssertEqual(StoryStoreImpl().getOrCreateStoryContextAssociatedData(for: recipient.aci!, tx: tx).isHidden, isStoryHidden)
    }

    func testRegisteredBlockedContact() async throws {
        try await runTest(backupName: "registered-blocked-contact") { sdsTx, tx in
            let allRecipients = depBridge.recipientDatabaseTable.allRecipients(tx: tx)
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
            let allRecipients = depBridge.recipientDatabaseTable.allRecipients(tx: tx)
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

final class MessageBackupDistributionListTest: MessageBackupIntegrationTestCase {
    typealias ListValidationBlock = ((TSPrivateStoryThread) -> Void)

    let storyStore = StoryStoreImpl()
    let threadStore = ThreadStoreImpl()

    func testDistributionList() async throws {
        func skipTest() throws {
            /// This test is failing because the `.binproto` hardcodes a
            /// timestamp, and these assertions care about the time between
            /// "now" and that timestamp, which is not stable.
            ///
            /// Disabling for now to unblock CI – we can re-enable once we have
            /// a plan for timestamp-agnosticism in Backup tests.
            throw XCTSkip()
        }

        /// Can't do a direct `throw` here, because the compiler complains that
        /// the code below won't be executed. Who's smarter now, compiler??
        try skipTest()

        try await runTest(backupName: "story-distribution-list") { sdsTx, tx in
            let deletedStories = storyStore.getAllDeletedStories(tx: tx)
            XCTAssertEqual(deletedStories.count, 2)

            let validationBlocks: [UUID: ListValidationBlock] = [
                UUID(TSPrivateStoryThread.myStoryUniqueId): { thread in
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

            try threadStore.enumerateStoryThreads(tx: tx) { thread, stop in
                do {
                    let validationBlock = try XCTUnwrap(validationBlocks[UUID(thread.uniqueId)])
                    validationBlock(thread)
                } catch {
                    XCTFail("Missing validation block")
                }
            }
        }
    }
}

// MARK: -

private extension RecipientDatabaseTable {
    func allRecipients(tx: any DBReadTransaction) -> [SignalRecipient] {
        var result = [SignalRecipient]()
        enumerateAll(tx: tx) { result.append($0) }
        return result
    }
}

// MARK: _

private extension UUID {
    init(_ string: String) {
        self.init(uuidString: string)!
    }
}

private extension Aci {
    /// Corresponds to base64 data `QHaZXgUxQEKp5B5np33zWA==`.
    static let fixture: Aci = Aci("4076995E-0531-4042-A9E4-1E67A77DF358")

    convenience init(_ string: String) {
        self.init(fromUUID: UUID(string))
    }
}

private extension Pni {
    /// Corresponds to base64 data `JvwCorpYSn2wgZ2iOXFXCg==`.
    static let fixture: Pni = Pni("26FC02A2-BA58-4A7D-B081-9DA23971570A")

    convenience init(_ string: String) {
        self.init(fromUUID: UUID(string))
    }
}
