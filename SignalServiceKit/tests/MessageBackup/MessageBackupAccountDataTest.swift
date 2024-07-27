//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

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
            XCTAssertFalse(deps.linkPreviewSettingStore.areLinkPreviewsEnabled(tx: tx))
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
