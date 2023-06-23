//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
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
        let isThreadBlocked = databaseStorage.read { blockingManager.isThreadBlocked(thread, transaction: $0) }

        guard !isThreadBlocked else {
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard !isBlocked else { return }
                self?.tryToSendMessage(builder)
            }
            return
        }

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
                builder.expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)
            }

            let message = builder.build(transaction: transaction)
            message.anyInsert(transaction: transaction)
            Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

            if message.hasRenderableContent() { thread.donateSendMessageIntent(for: message, transaction: transaction) }

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

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.storyReactionEmoji = reaction
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress

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
        let sheet = EmojiPickerSheet(message: nil) { [weak self] selectedEmoji in
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

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.messageBody = messageBody.text
        builder.bodyRanges = messageBody.ranges
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress

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
