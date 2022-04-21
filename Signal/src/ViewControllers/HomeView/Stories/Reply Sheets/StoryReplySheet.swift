//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalUI

protocol StoryReplySheet: OWSViewController, StoryReplyInputToolbarDelegate, MessageReactionPickerDelegate {
    var inputToolbar: StoryReplyInputToolbar { get }
    var storyMessage: StoryMessage { get }
    var thread: TSThread? { get }

    var dismissHandler: (() -> Void)? { get set }

    var reactionPickerBackdrop: UIView? { get set }
    var reactionPicker: MessageReactionPicker? { get set }

    func didSendMessage()
}

// MARK: - Sending

extension StoryReplySheet {
    func tryToSendMessage(_ message: TSOutgoingMessage) {
        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }
        let isThreadBlocked = databaseStorage.read { blockingManager.isThreadBlocked(thread, transaction: $0) }

        guard !isThreadBlocked else {
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard !isBlocked else { return }
                self?.tryToSendMessage(message)
            }
            return
        }

        guard !SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: thread.recipientAddresses,
            confirmationText: SafetyNumberStrings.confirmSendButton,
            completion: { [weak self] didConfirmIdentity in
                guard didConfirmIdentity else { return }
                self?.tryToSendMessage(message)
            }
        ) else { return }

        ThreadUtil.enqueueSendAsyncWrite { [weak self] transaction in
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(thread: thread, setDefaultTimerIfNecessary: false, transaction: transaction)

            message.anyInsert(transaction: transaction)

            Self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

            transaction.addAsyncCompletionOnMain { self?.didSendMessage() }
        }
    }

    func tryToSendReaction(_ reaction: String) {
        owsAssertDebug(reaction.isSingleEmoji)

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.storyReactionEmoji = reaction
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress

        tryToSendMessage(builder.build())
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

        let sheet = EmojiPickerSheet { [weak self] selectedEmoji in
            guard let selectedEmoji = selectedEmoji else { return }
            self?.tryToSendReaction(selectedEmoji.rawValue)
        }
        present(sheet, animated: true)
    }
}

// MARK: - StoryReplyInputToolbarDelegate

extension StoryReplySheet {
    func storyReplyInputToolbarDidTapSend(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        guard let messageBody = storyReplyInputToolbar.messageBody, !messageBody.text.isEmpty else {
            return owsFailDebug("Unexpectedly missing message body")
        }

        guard let thread = thread else {
            return owsFailDebug("Unexpectedly missing thread")
        }

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.messageBody = messageBody.text
        builder.bodyRanges = messageBody.ranges
        builder.storyTimestamp = NSNumber(value: storyMessage.timestamp)
        builder.storyAuthorAddress = storyMessage.authorAddress

        tryToSendMessage(builder.build())
    }

    func storyReplyInputToolbarDidTapReact(_ storyReplyInputToolbar: StoryReplyInputToolbar) {
        presentReactionPicker()
    }

    func storyReplyInputToolbarDidBeginEditing(_ storyReplyInputToolbar: StoryReplyInputToolbar) {}
    func storyReplyInputToolbarHeightDidChange(_ storyReplyInputToolbar: StoryReplyInputToolbar) {}

    func storyReplyInputToolbarMentionPickerPossibleAddresses(_ storyReplyInputToolbar: StoryReplyInputToolbar) -> [SignalServiceAddress] {
        return thread?.recipientAddresses ?? []
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
