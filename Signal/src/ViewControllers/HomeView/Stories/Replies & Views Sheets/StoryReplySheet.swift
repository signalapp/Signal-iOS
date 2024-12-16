//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

protocol StoryReplySheet: OWSViewController, StoryReplyInputToolbarDelegate, MessageReactionPickerDelegate {
    var bottomBar: UIView { get }
    var inputToolbar: StoryReplyInputToolbar { get }
    var storyMessage: StoryMessage { get }
    var thread: TSThread? { get }

    var reactionPickerBackdrop: UIView? { get set }
    var reactionPicker: MessageReactionPicker? { get set }

    func didSendMessage()
}

// MARK: - Sending

extension StoryReplySheet {
    func tryToSendMessage(_ builder: TSOutgoingMessageBuilder) {
        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }
        let isThreadBlocked = SSKEnvironment.shared.databaseStorageRef.read { SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: $0) }

        guard !isThreadBlocked else {
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard !isBlocked else { return }
                self?.tryToSendMessage(builder)
            }
            return
        }

        // Note: Because we drop all incoming and existing stories from hidden recipients, we do not
        // specially handle the hidden recipient case here. It is possible we could encounter an edge
        // case, such as if a contact is being hidden on another device while we're replying to their
        // story on this device. If this happens, we accept that the hide will be undone if the
        // ordering is hide -> reply.

        guard !SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: thread.recipientAddressesWithSneakyTransaction,
            confirmationText: SafetyNumberStrings.confirmSendButton,
            completion: { [weak self] didConfirmIdentity in
                guard didConfirmIdentity else { return }
                self?.tryToSendMessage(builder)
            }
        ) else { return }

        // We only use the thread's DM timer for 1:1 story replies,
        // group replies last for the lifetime of the story.
        let shouldUseThreadDMTimer = !thread.isGroupThread

        ThreadUtil.enqueueSendAsyncWrite { [weak self] transaction in
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                thread,
                setDefaultTimerIfNecessary: shouldUseThreadDMTimer,
                tx: transaction
            )

            if shouldUseThreadDMTimer {
                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction.asV2Read)
                builder.expiresInSeconds = dmConfig.durationSeconds
                builder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)
            }

            let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(builder.build(transaction: transaction))
            guard let preparedMessage = try? unpreparedMessage.prepare(tx: transaction) else {
                owsFailDebug("Failed to prepare message")
                return
            }
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)

            if let message = preparedMessage.messageForIntentDonation(tx: transaction) {
                thread.donateSendMessageIntent(for: message, transaction: transaction)
            }

            transaction.addAsyncCompletionOnMain { self?.didSendMessage() }
        }
    }

    func tryToSendReaction(_ reaction: String) {
        owsAssertDebug(reaction.isSingleEmoji)

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        owsAssertDebug(
            !storyMessage.authorAddress.isSystemStoryAddress,
            "Should be impossible to reply to system stories"
        )

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            storyAuthorAci: storyMessage.authorAci,
            storyTimestamp: storyMessage.timestamp,
            storyReactionEmoji: reaction
        )

        tryToSendMessage(builder)

        ReactionFlybyAnimation(reaction: reaction).present(from: self)
    }
}

// MARK: - MessageReactionPickerDelegate

extension StoryReplySheet {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int) {
        dismissReactionPicker()

        tryToSendReaction(reaction)
    }

    func didSelectAnyEmoji() {
        dismissReactionPicker()

        // nil is intentional, the message is for showing other reactions already
        // on the message, which we don't wanna do for stories.
        let sheet = EmojiPickerSheet(message: nil, forceDarkTheme: true) { [weak self] selectedEmoji in
            guard let selectedEmoji = selectedEmoji else { return }
            self?.tryToSendReaction(selectedEmoji.rawValue)
        }
        present(sheet, animated: true)
    }
}

// MARK: - StoryReplyInputToolbarDelegate

extension StoryReplySheet {
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        guard let messageBody = storyReplyInputToolbar.messageBodyForSending, !messageBody.text.isEmpty else {
            return owsFailDebug("Unexpectedly missing message body")
        }

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }
        owsAssertDebug(
            !storyMessage.authorAddress.isSystemStoryAddress,
            "Should be impossible to reply to system stories"
        )

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: messageBody.text,
            bodyRanges: messageBody.ranges,
            storyAuthorAci: storyMessage.authorAci,
            storyTimestamp: storyMessage.timestamp
        )

        tryToSendMessage(builder)
    }

    func storyReplyInputToolbarDidTapReact(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        presentReactionPicker()
    }

    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar) {}
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar) {}

    func storyReplyInputToolbarMentionPickerPossibleAddresses(_ storyReplyInputToolbar: StoryReplyInputToolbar, tx: DBReadTransaction) -> [SignalServiceAddress] {
        guard let thread = thread, thread.isGroupThread else { return [] }
        return thread.recipientAddresses(with: SDSDB.shimOnlyBridge(tx))
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

// MARK: - Reaction Picker

extension StoryReplySheet {
    func presentReactionPicker() {
        guard self.reactionPicker == nil else { return }

        let backdrop = OWSButton { [weak self] in
            self?.dismissReactionPicker()
        }
        backdrop.backgroundColor = .ows_blackAlpha40
        view.addSubview(backdrop)
        backdrop.autoPinEdgesToSuperviewEdges()
        backdrop.alpha = 0
        self.reactionPickerBackdrop = backdrop

        let reactionPicker = MessageReactionPicker(selectedEmoji: nil, delegate: self, forceDarkTheme: true)

        view.addSubview(reactionPicker)
        reactionPicker.autoPinEdge(.bottom, to: .top, of: inputToolbar, withOffset: -15)
        reactionPicker.autoPinEdge(toSuperviewEdge: .trailing, withInset: 12)

        reactionPicker.playPresentationAnimation(duration: 0.2)

        UIView.animate(withDuration: 0.2) { backdrop.alpha = 1 }

        self.reactionPicker = reactionPicker
    }

    func dismissReactionPicker() {
        UIView.animate(withDuration: 0.2) {
            self.reactionPickerBackdrop?.alpha = 0
        } completion: { _ in
            self.reactionPickerBackdrop?.removeFromSuperview()
            self.reactionPickerBackdrop = nil
        }

        reactionPicker?.playDismissalAnimation(duration: 0.2) {
            self.reactionPicker?.removeFromSuperview()
            self.reactionPicker = nil
        }
    }
}
