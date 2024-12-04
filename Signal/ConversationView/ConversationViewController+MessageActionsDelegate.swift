//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFAudio
import SignalServiceKit
import SignalUI

extension ConversationViewController: MessageActionsDelegate {
    func messageActionsEditItem(_ itemViewModel: CVItemViewModelImpl) {
        let hasUnsavedDraft: Bool

        if let inputToolbar {
            hasUnsavedDraft = inputToolbar.hasUnsavedDraft
        } else {
            owsFailDebug("Missing inputToolbar.")
            hasUnsavedDraft = false
        }

        if hasUnsavedDraft {
            let sheet = ActionSheetController(
                title: OWSLocalizedString("DISCARD_DRAFT_CONFIRMATION_TITLE", comment: "Title for confirmation prompt when discarding a draft before editing a message"),
                message: OWSLocalizedString("DISCARD_DRAFT_CONFIRMATION_MESSAGE", comment: "Message/subtitle for confirmation prompt when discarding a draft before editing a message")
            )
            sheet.addAction(
                ActionSheetAction(title: CommonStrings.discardButton, style: .destructive) { [self] _ in
                    populateMessageEdit(itemViewModel)
                }
            )
            sheet.addAction(.cancel)
            present(sheet, animated: true)
        } else {
            populateMessageEdit(itemViewModel)
        }
    }

    func populateMessageEdit(_ itemViewModel: CVItemViewModelImpl) {
        guard let message = itemViewModel.interaction as? TSOutgoingMessage else {
            return owsFailDebug("Invalid interaction.")
        }

        var editValidationError: EditSendValidationError?
        var quotedReplyModel: DraftQuotedReplyModel?
        SSKEnvironment.shared.databaseStorageRef.read { transaction in

            // If edit send validation fails (timeframe expired,
            // too many edits, etc), display a message here.
            if let error = context.editManager.validateCanSendEdit(
                targetMessageTimestamp: message.timestamp,
                thread: self.thread,
                tx: transaction.asV2Read
            ) {
                editValidationError = error
                return
            }

            if let quotedMessage = message.quotedMessage {
                let originalMessage = (quotedMessage.timestampValue?.uint64Value).flatMap {
                    return InteractionFinder.findMessage(
                        withTimestamp: $0,
                        threadId: message.uniqueThreadId,
                        author: quotedMessage.authorAddress,
                        transaction: transaction
                    )
                }
                if
                    let originalMessage,
                    originalMessage is OWSPaymentMessage
                {
                    quotedReplyModel = DraftQuotedReplyModel.forEditingOriginalPaymentMessage(
                        originalMessage: originalMessage,
                        replyMessage: message,
                        quotedReply: quotedMessage,
                        tx: transaction
                    )
                } else {
                    quotedReplyModel = DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReplyForEditing(
                        quotedReplyMessage: message,
                        quotedReply: quotedMessage,
                        originalMessage: originalMessage,
                        tx: transaction.asV2Read
                    )
                }
            }
        }

        if let editValidationError {
            OWSActionSheets.showActionSheet(message: editValidationError.localizedDescription)
        } else {
            inputToolbar?.quotedReplyDraft = quotedReplyModel
            inputToolbar?.editTarget = message

            inputToolbar?.editThumbnail = nil
            let imageStream = itemViewModel.bodyMediaAttachmentStreams.first(where: {
                $0.contentType.isImage
            })
            if let imageStream {
                Task {
                    guard let image = await imageStream.thumbnailImage(quality: .small) else {
                        owsFailDebug("Could not load thumnail.")
                        return
                    }
                    guard let inputToolbar,
                          inputToolbar.shouldShowEditUI else { return }
                    inputToolbar.editThumbnail = image
                }
            }

            inputToolbar?.beginEditingMessage()
        }
    }

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

        let detailVC = MessageDetailViewController(
            message: message,
            threadViewModel: self.threadViewModel,
            spoilerState: self.viewState.spoilerState,
            editManager: self.context.editManager,
            thread: thread
        )
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
            detailVC = MessageDetailViewController(
                message: message,
                threadViewModel: self.threadViewModel,
                spoilerState: self.viewState.spoilerState,
                editManager: self.context.editManager,
                thread: thread
            )
            detailVC.detailDelegate = self
            conversationSplitViewController?.navigationTransitionDelegate = detailVC
        }

        navigationController?.pushViewController(detailVC, animated: true)
    }

    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl) {
        populateReplyForMessage(itemViewModel)
    }

    public func populateReplyForMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        self.uiMode = .normal

        let load: () -> DraftQuotedReplyModel? = {
            guard let message = itemViewModel.interaction as? TSMessage else {
                return nil
            }
            return SSKEnvironment.shared.databaseStorageRef.read { transaction in
                if message is OWSPaymentMessage {
                    return DraftQuotedReplyModel.fromOriginalPaymentMessage(message, tx: transaction)
                }
                return DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(
                    originalMessage: message,
                    tx: transaction.asV2Read
                )
            }
        }
        guard let quotedReply = load() else {
            owsFailDebug("Could not build quoted reply.")
            return
        }

        inputToolbar.editTarget = nil
        inputToolbar.quotedReplyDraft = quotedReply
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
        itemViewModel.interaction.presentDeletionActionSheet(from: self)
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
            case .messageBody(let messageBody):
                return messageBody.utterance
            }
        }()

        AppEnvironment.shared.speechManagerRef.speak(utterance)
    }

    func messageActionsStopSpeakingItem(_ itemViewModel: CVItemViewModelImpl) {
        AppEnvironment.shared.speechManagerRef.stop()
    }

    func messageActionsShowPaymentDetails(_ itemViewModel: CVItemViewModelImpl) {
        guard let contactAddress = (thread as? TSContactThread)?.contactAddress else {
            owsFailDebug("Should be contact thread")
            return
        }
        let contactName = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: contactAddress, tx: tx).resolvedValue()
        }

        let paymentHistoryItem: PaymentsHistoryItem
        if
            let archivedPayment = itemViewModel.archivedPaymentAttachment?.archivedPayment,
            let item = ArchivedPaymentHistoryItem(
                archivedPayment: archivedPayment,
                address: contactAddress,
                displayName: contactName,
                interaction: itemViewModel.interaction
            )
        {
            paymentHistoryItem = item
        } else if let paymentModel = itemViewModel.paymentAttachment?.model {
            paymentHistoryItem = PaymentsHistoryModelItem(paymentModel: paymentModel, displayName: contactName)
        } else {
            owsFailDebug("We should have a matching TSPaymentModel at this point")
            return
        }

        let paymentsDetailViewController = PaymentsDetailViewController(paymentItem: paymentHistoryItem)
        navigationController?.pushViewController(paymentsDetailViewController, animated: true)
    }
}
