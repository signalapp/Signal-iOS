//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFAudio

extension ConversationViewController: MessageActionsDelegate {
    func messageActionsShowDetailsForItem(_ itemViewModel: CVItemViewModelImpl) {
        showDetailView(itemViewModel)
    }

    func prepareDetailViewForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let message = itemViewModel.interaction as? TSMessage else {
            return owsFailDebug("Invalid interaction.")
        }

        guard let panHandler = panHandler else {
            return owsFailDebug("Missing panHandler")
        }

        let detailVC = MessageDetailViewController(message: message, thread: thread)
        detailVC.detailDelegate = self
        conversationSplitViewController?.navigationTransitionDelegate = detailVC
        panHandler.messageDetailViewController = detailVC
    }

    func showDetailView(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let message = itemViewModel.interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return
        }

        let panHandler = viewState.panHandler

        let detailVC: MessageDetailViewController
        if let panHandler = panHandler,
           let messageDetailViewController = panHandler.messageDetailViewController,
           messageDetailViewController.message.uniqueId == message.uniqueId {
            detailVC = messageDetailViewController
            detailVC.pushPercentDrivenTransition = panHandler.percentDrivenTransition
        } else {
            detailVC = MessageDetailViewController(message: message, thread: thread)
            detailVC.detailDelegate = self
            conversationSplitViewController?.navigationTransitionDelegate = detailVC
        }

        navigationController?.pushViewController(detailVC, animated: true)
    }

    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl) {
        populateReplyForMessage(itemViewModel)
    }

    public func addOrRemoveEmojiFromDoubleTap(_ itemViewModel: CVItemViewModelImpl) {
        var firstEmoji: String? = nil
        var isRemoving: Bool = false
        SDSDatabaseStorage.shared.read { transaction in
            firstEmoji = ReactionManager.getFirstEmojiFromEmojiSet(transaction: transaction)
            isRemoving = false
            if let localUserEmoji = itemViewModel.reactionState?.localUserEmoji, localUserEmoji == firstEmoji {
                isRemoving = true
            }
        }

        guard let firstEmoji = firstEmoji else {
            owsFailDebug("Could not read emoji from database")
            return
        }
        if thread.canSendReactionToThread {
            let reactionBarAccessory = ContextMenuRectionBarAccessory(thread: self.thread, itemViewModel: itemViewModel)
            reactionBarAccessory.didSelectReactionHandler = { [weak self] (message: TSMessage, reaction: String, isRemoving: Bool) in
                guard let self = self else {
                    owsFailDebug("conversationViewController was unexpectedly nil")
                    return
                }
                self.databaseStorage.asyncWrite { transaction in
                    ReactionManager.localUserReacted(
                        to: message,
                        emoji: reaction,
                        isRemoving: isRemoving,
                        transaction: transaction
                    )
                }
            }
            reactionBarAccessory.didSelectReaction(reaction: firstEmoji, isRemoving: isRemoving, inPosition: 0)
        }
    }

    public func populateReplyForMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("")
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        self.uiMode = .normal

        let load = {
            Self.databaseStorage.read { transaction in
                OWSQuotedReplyModel.quotedReplyForSending(withItem: itemViewModel,
                                                          transaction: transaction)
            }
        }
        guard let quotedReply = load() else {
            owsFailDebug("Could not build quoted reply.")
            return
        }

        inputToolbar.quotedReply = quotedReply
        inputToolbar.beginEditingMessage()
    }

    func messageActionsForwardItem(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        ForwardMessageViewController.present(forItemViewModels: [itemViewModel],
                                             from: self,
                                             delegate: self)
    }

    func messageActionsStartedSelect(initialItem itemViewModel: CVItemViewModelImpl) {
        uiMode = .selection

        selectionState.add(itemViewModel: itemViewModel, selectionType: .allContent)
    }

    func messageActionsDeleteItem(_ itemViewModel: CVItemViewModelImpl) {
        guard let message = itemViewModel.interaction as? TSMessage else { return }
        message.presentDeletionActionSheet(from: self)
    }

    func messageActionsSpeakItem(_ itemViewModel: CVItemViewModelImpl) {
        guard let textValue = itemViewModel.displayableBodyText?.fullTextValue else {
            return
        }

        let utterance: AVSpeechUtterance = {
            switch textValue {
            case .text(let text):
                return AVSpeechUtterance(string: text)
            case .attributedText(let attributedText):
                return AVSpeechUtterance(attributedString: attributedText)
            }
        }()

        self.speechManager.speak(utterance)
    }

    func messageActionsStopSpeakingItem(_ itemViewModel: CVItemViewModelImpl) {
        self.speechManager.stop()
    }
}
