//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import SignalUI
import UIKit

protocol StoryReplySheet: OWSViewController, StoryReplyInputToolbarDelegate, MessageReactionPickerDelegate {
    var bottomBar: UIView { get }
    var inputToolbar: StoryReplyInputToolbar { get }
    var storyMessage: StoryMessage { get }
    var thread: TSThread? { get }

    func didSendMessage()
}

// MARK: - Sending

extension StoryReplySheet {
    func tryToSendMessage(
        _ builder: TSOutgoingMessageBuilder,
        messageBody: ValidatedMessageBody?,
    ) {
        guard let thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }
        let isThreadBlocked = SSKEnvironment.shared.databaseStorageRef.read { SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: $0) }

        guard !isThreadBlocked else {
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard !isBlocked else { return }
                self?.tryToSendMessage(builder, messageBody: messageBody)
            }
            return
        }

        // Note: Because we drop all incoming and existing stories from hidden recipients, we do not
        // specially handle the hidden recipient case here. It is possible we could encounter an edge
        // case, such as if a contact is being hidden on another device while we're replying to their
        // story on this device. If this happens, we accept that the hide will be undone if the
        // ordering is hide -> reply.

        guard
            !SafetyNumberConfirmationSheet.presentIfNecessary(
                addresses: thread.recipientAddressesWithSneakyTransaction,
                confirmationText: SafetyNumberStrings.confirmSendButton,
                forceDarkTheme: true,
                completion: { [weak self] didConfirmIdentity in
                    guard didConfirmIdentity else { return }
                    self?.tryToSendMessage(builder, messageBody: messageBody)
                },
            ) else { return }

        // We only use the thread's DM timer for 1:1 story replies,
        // group replies last for the lifetime of the story.
        let shouldUseThreadDMTimer = !thread.isGroupThread

        ThreadUtil.enqueueSendAsyncWrite { [weak self] transaction in
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                thread,
                setDefaultTimerIfNecessary: shouldUseThreadDMTimer,
                tx: transaction,
            )

            if shouldUseThreadDMTimer {
                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)
                builder.expiresInSeconds = dmConfig.durationSeconds
                builder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)
            }

            let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
                builder.build(transaction: transaction),
                body: messageBody,
            )
            guard let preparedMessage = try? unpreparedMessage.prepare(tx: transaction) else {
                owsFailDebug("Failed to prepare message")
                return
            }
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)

            if let message = preparedMessage.messageForIntentDonation(tx: transaction) {
                thread.donateSendMessageIntent(for: message, transaction: transaction)
            }

            transaction.addSyncCompletion {
                Task { @MainActor in
                    self?.didSendMessage()
                }
            }
        }
    }

    func tryToSendReaction(_ reaction: String) {
        owsAssertDebug(reaction.isSingleEmoji)

        guard let thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        owsAssertDebug(
            !storyMessage.authorAddress.isSystemStoryAddress,
            "Should be impossible to reply to system stories",
        )

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            storyAuthorAci: storyMessage.authorAci,
            storyTimestamp: storyMessage.timestamp,
            storyReactionEmoji: reaction,
        )

        tryToSendMessage(builder, messageBody: nil)

        ReactionFlybyAnimation(reaction: reaction).present(from: self)
    }
}

// MARK: - MessageReactionPickerDelegate

extension StoryReplySheet {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int) {
        tryToSendReaction(reaction)
    }

    func didSelectAnyEmoji() {
        // nil is intentional, the message is for showing other reactions already
        // on the message, which we don't wanna do for stories.
        let sheet = EmojiPickerSheet(message: nil) { [weak self] selectedEmoji in
            guard let selectedEmoji else { return }
            self?.tryToSendReaction(selectedEmoji.rawValue)
        }
        sheet.overrideUserInterfaceStyle = .dark
        present(sheet, animated: true)
    }
}

// MARK: - StoryReplyInputToolbarDelegate

extension StoryReplySheet {
    @MainActor
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar) async throws {
        guard
            let originalMessageBody = storyReplyInputToolbar.messageBodyForSending,
            !originalMessageBody.text.isEmpty
        else {
            throw OWSAssertionError("Unexpectedly missing message body")
        }

        let messageBody = try await DependenciesBridge.shared.attachmentContentValidator
            .prepareOversizeTextIfNeeded(originalMessageBody)

        guard let thread else {
            throw OWSAssertionError("Unexpectedly missing thread")
        }
        owsAssertDebug(
            !storyMessage.authorAddress.isSystemStoryAddress,
            "Should be impossible to reply to system stories",
        )

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: messageBody,
            storyAuthorAci: storyMessage.authorAci,
            storyTimestamp: storyMessage.timestamp,
        )

        tryToSendMessage(builder, messageBody: messageBody)
    }

    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar) {}
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar) {}

    func storyReplyInputToolbarMentionPickerPossibleAcis(_ storyReplyInputToolbar: StoryReplyInputToolbar, tx: DBReadTransaction) -> [Aci] {
        guard let thread, thread.isGroupThread else { return [] }
        return thread.recipientAddresses(with: tx).compactMap(\.aci)
    }

    func storyReplyInputToolbarMentionCacheInvalidationKey() -> String {
        return thread?.uniqueId ?? UUID().uuidString
    }

    func storyReplyInputToolbarMentionPickerParentView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView? {
        view
    }

    func storyReplyInputToolbarMentionPickerReferenceView(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> UIView? {
        bottomBar
    }
}
