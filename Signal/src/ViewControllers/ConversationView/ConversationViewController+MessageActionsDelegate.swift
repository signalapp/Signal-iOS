//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

extension ConversationViewController: MessageActionsDelegate {
    func messageActionsShowDetailsForItem(_ itemViewModel: CVItemViewModelImpl) {
        showDetailView(itemViewModel)
    }

    func showDetailView(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let message = itemViewModel.interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return
        }

        let detailVC = MessageDetailViewController(itemViewModel: itemViewModel,
                                                   message: message,
                                                   thread: thread,
                                                   mode: .focusOnMetadata)
        detailVC.delegate = self
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl) {
        populateReplyForMessage(itemViewModel)
    }

    @objc
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
            Self.databaseStorage.uiRead { transaction in
                OWSQuotedReplyModel.quotedReplyForSending(withItem: itemViewModel, transaction: transaction)
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
        ForwardMessageNavigationController.present(for: itemViewModel, from: self, delegate: self)
    }

    func messageActionsStartedSelect(initialItem itemViewModel: CVItemViewModelImpl) {
        self.scrollContinuity = .bottom

        uiMode = .selection

        self.addToSelection(itemViewModel.interaction.uniqueId)
    }

    func messageActionsDeleteItem(_ itemViewModel: CVItemViewModelImpl) {
        let actionSheetController = ActionSheetController(message: NSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_TITLE",
            comment: "The title for the action sheet asking who the user wants to delete the message for."
        ))

        let deleteForMeAction = ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive
        ) { _ in
            itemViewModel.deleteAction()
        }
        actionSheetController.addAction(deleteForMeAction)

        if canBeRemotelyDeleted(item: itemViewModel),
           let message = itemViewModel.interaction as? TSOutgoingMessage {

            let deleteForEveryoneAction = ActionSheetAction(
                title: NSLocalizedString(
                    "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
                    comment: "The title for the action that deletes a message for all users in the conversation."
                ),
                style: .destructive
            ) { [weak self] _ in
                self?.showDeleteForEveryoneConfirmationIfNecessary {
                    guard let self = self else { return }

                    let deleteMessage = TSOutgoingDeleteMessage(thread: self.thread, message: message)

                    self.databaseStorage.write { transaction in
                        // Reset the sending states, so we can render the sending state of the deleted message.
                        // TSOutgoingDeleteMessage will automatically pass through it's send state to the message
                        // record that it is deleting.
                        message.updateWith(recipientAddressStates: deleteMessage.recipientAddressStates, transaction: transaction)
                        message.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
                        SSKEnvironment.shared.messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: transaction)
                    }
                }
            }
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheetController)
    }
}
