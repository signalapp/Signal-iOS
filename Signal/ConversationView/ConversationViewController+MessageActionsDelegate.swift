//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFAudio
public import SignalServiceKit
import LibSignalClient
import SignalUI

extension ConversationViewController: MessageActionsDelegate {
    func messageActionsEditItem(_ itemViewModel: CVItemViewModelImpl) {
        let hasUnsavedDraft: Bool

        if let inputToolbar {
            hasUnsavedDraft = inputToolbar.hasUnsavedDraft
        } else {
            hasUnsavedDraft = false
        }

        if hasUnsavedDraft {
            let sheet = ActionSheetController(
                title: OWSLocalizedString("DISCARD_DRAFT_CONFIRMATION_TITLE", comment: "Title for confirmation prompt when discarding a draft before editing a message"),
                message: OWSLocalizedString("DISCARD_DRAFT_CONFIRMATION_MESSAGE", comment: "Message/subtitle for confirmation prompt when discarding a draft before editing a message"),
            )
            sheet.addAction(
                ActionSheetAction(title: CommonStrings.discardButton, style: .destructive) { [self] _ in
                    populateMessageEdit(itemViewModel)
                },
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
            if
                let error = context.editManager.validateCanSendEdit(
                    targetMessageTimestamp: message.timestamp,
                    thread: self.thread,
                    tx: transaction,
                )
            {
                editValidationError = error
                return
            }

            if let quotedMessage = message.quotedMessage {
                let originalMessage = (quotedMessage.timestampValue?.uint64Value).flatMap {
                    return InteractionFinder.findMessage(
                        withTimestamp: $0,
                        threadId: message.uniqueThreadId,
                        author: quotedMessage.authorAddress,
                        transaction: transaction,
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
                        tx: transaction,
                    )
                } else {
                    quotedReplyModel = DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReplyForEditing(
                        quotedReplyMessage: message,
                        quotedReply: quotedMessage,
                        originalMessage: originalMessage,
                        tx: transaction,
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
                    guard let inputToolbar, inputToolbar.isEditingMessage else { return }
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

        guard let panHandler else {
            return owsFailDebug("Missing panHandler")
        }

        let detailVC = MessageDetailViewController(
            message: message,
            threadViewModel: self.threadViewModel,
            spoilerState: self.viewState.spoilerState,
            editManager: self.context.editManager,
            thread: thread,
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
        if
            let panHandler,
            let messageDetailViewController = panHandler.messageDetailViewController,
            messageDetailViewController.message.uniqueId == message.uniqueId
        {
            detailVC = messageDetailViewController
            detailVC.pushPercentDrivenTransition = panHandler.percentDrivenTransition
        } else {
            detailVC = MessageDetailViewController(
                message: message,
                threadViewModel: self.threadViewModel,
                spoilerState: self.viewState.spoilerState,
                editManager: self.context.editManager,
                thread: thread,
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

        guard let inputToolbar else {
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
                    tx: transaction,
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

        ForwardMessageViewController.present(forItemViewModel: itemViewModel, from: self, delegate: self)
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
                interaction: itemViewModel.interaction,
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

    func messageActionsEndPoll(_ itemViewModel: CVItemViewModelImpl) {
        if let groupThread = self.thread as? TSGroupThread, let poll = itemViewModel.componentState.poll?.state.poll {
            do {
                try DependenciesBridge.shared.pollMessageManager.sendPollTerminateMessage(poll: poll, thread: groupThread)
            } catch {
                Logger.error("Failed to end poll: \(error)")
            }
        }
    }

    func sendPinMessageChange(pinMessage: TSOutgoingMessage) async throws {
        let db = DependenciesBridge.shared.db
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef
        let pinnedMessageManager = DependenciesBridge.shared.pinnedMessageManager

        let sendPromise = await db.awaitableWrite { tx in
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: pinMessage,
            )

            return messageSenderJobQueue.add(
                .promise,
                message: preparedMessage,
                transaction: tx,
            )
        }

        do {
            try await sendPromise.awaitable()
        } catch is MessageSenderNoSuchSignalRecipientError, is MessageSenderErrorNoValidRecipients {
            Logger.info("Recipient not found, still showing a pin success locally")
            db.write { tx in
                // since message was never sent, use current time as the sent time.
                let sentTimestamp = Date.ows_millisecondTimestamp()

                if
                    let _pinMessage = pinMessage as? OutgoingPinMessage,
                    let aciBinary = _pinMessage.targetMessageAuthorAciBinary,
                    let targetAuthorAci = try? Aci.parseFrom(serviceIdBinary: aciBinary)
                {
                    let expiresAtMs: UInt64? = _pinMessage.pinDurationSeconds > 0 ? Date.ows_millisecondTimestamp() + UInt64(_pinMessage.pinDurationSeconds * 1000) : nil

                    pinnedMessageManager.applyPinMessageChangeToLocalState(
                        targetTimestamp: _pinMessage.targetMessageTimestamp,
                        targetAuthorAci: targetAuthorAci,
                        expiresAt: expiresAtMs,
                        isPin: true,
                        sentTimestamp: sentTimestamp,
                        tx: tx,
                    )
                } else if
                    let _unpinMessage = pinMessage as? OutgoingUnpinMessage,
                    let aciBinary = _unpinMessage.targetMessageAuthorAciBinary,
                    let targetAuthorAci = try? Aci.parseFrom(serviceIdBinary: aciBinary)
                {

                    pinnedMessageManager.applyPinMessageChangeToLocalState(
                        targetTimestamp: _unpinMessage.targetMessageTimestamp,
                        targetAuthorAci: targetAuthorAci,
                        expiresAt: nil,
                        isPin: false,
                        sentTimestamp: sentTimestamp,
                        tx: tx,
                    )
                }
            }
        }
    }

    func queuePinMessageChangeWithModal(
        message: TSMessage,
        pinMessage: TSOutgoingMessage,
        modalDelegate: UIViewController,
        completion: (() -> Void)?,
    ) async {
        do {
            try await ModalActivityIndicatorViewController.presentAndPropagateResult(from: modalDelegate) {
                try await self.sendPinMessageChange(pinMessage: pinMessage)
            }
        } catch {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "PINNED_MESSAGE_SEND_ERROR_SHEET_TITLE",
                    comment: "Title for error sheet shown if the pinned message failed to send",
                ),
                message: OWSLocalizedString(
                    "PINNED_MESSAGE_SEND_ERROR_SHEET_BODY",
                    comment: "Body for error sheet shown if the pinned message failed to send",
                ),
            )
            return
        }

        // Pinned messages are sorted from most -> least recent.
        // Reset the index to 0 if someone pins or unpins. This will
        // make sure we always show the most recent pin after a change.
        pinnedMessageIndex = 0
        completion?()
    }

    private func showPinExpiryActionSheet(completion: @escaping (TimeInterval?) -> Void) {
        let actionSheet = ActionSheetController(
            title: nil,
            message: OWSLocalizedString(
                "PINNED_MESSAGES_EXPIRY_SHEET_TITLE",
                comment: "Title for an action sheet to indicate how long to keep the pin active",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "PINNED_MESSAGES_24_HOURS",
                comment: "Option in pinned message action sheet to pin for 24 hours.",
            ),
            handler: { _ in
                completion(.day)
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "PINNED_MESSAGES_7_DAYS",
                comment: "Option in pinned message action sheet to pin for 7 days.",
            ),
            handler: { _ in
                completion(7 * .day)
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "PINNED_MESSAGES_30_DAYS",
                comment: "Option in pinned message action sheet to pin for 30 days.",
            ),
            handler: { _ in
                completion(30 * .day)
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "PINNED_MESSAGES_FOREVER",
                comment: "Option in pinned message action sheet to pin with no expiry.",
            ),
            handler: { _ in
                completion(nil)
            },
        ))
        actionSheet.addAction(.cancel)
        presentActionSheet(actionSheet)
    }

    private func handleActionPin(message: TSMessage) {
        let pinnedMessageManager = DependenciesBridge.shared.pinnedMessageManager
        let db = DependenciesBridge.shared.db

        let choosePinExpiryAndSendWithOptionalDMWarning: () -> Void = {
            self.showPinExpiryActionSheet(completion: { expiryInSeconds in
                db.write { tx in
                    let pinMessage = pinnedMessageManager.getOutgoingPinMessage(
                        interaction: message,
                        thread: self.thread,
                        expiresAt: expiryInSeconds,
                        tx: tx,
                    )

                    guard let pinMessage else {
                        return
                    }

                    if pinnedMessageManager.shouldShowDisappearingMessageWarning(message: message, tx: tx) {
                        pinnedMessageManager.incrementDisappearingMessageWarningCount(tx: tx)
                        self.present(
                            PinDisappearingMessageViewController(
                                pinnedMessageManager: pinnedMessageManager,
                                db: DependenciesBridge.shared.db,
                                completion: {
                                    Task {
                                        await self.queuePinMessageChangeWithModal(
                                            message: message,
                                            pinMessage: pinMessage,
                                            modalDelegate: self,
                                            completion: nil,
                                        )
                                    }
                                },
                            ),
                            animated: true,
                        )
                    } else {
                        Task {
                            await self.queuePinMessageChangeWithModal(message: message, pinMessage: pinMessage, modalDelegate: self, completion: nil)
                        }
                    }
                }
            })
        }

        if threadViewModel.pinnedMessages.count >= RemoteConfig.current.pinnedMessageLimit {
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "PINNED_MESSAGE_REPLACE_OLDEST_TITLE",
                    comment: "Title for an action sheet confirming the user wants to replace oldest pinned message.",
                ),
                message: OWSLocalizedString(
                    "PINNED_MESSAGE_REPLACE_OLDEST_BODY",
                    comment: "Message for an action sheet confirming the user wants to replace oldest pinned message.",
                ),
            )
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "PINNED_MESSAGE_REPLACE_OLDEST_BUTTON",
                    comment: "Option in pinned message action sheet to replace oldest pin.",
                ),
                handler: { _ in
                    choosePinExpiryAndSendWithOptionalDMWarning()
                },
            ))
            actionSheet.addAction(.cancel)
            presentActionSheet(actionSheet)
        } else {
            choosePinExpiryAndSendWithOptionalDMWarning()
        }
    }

    public func handleActionUnpin(message: TSMessage, modalDelegate: UIViewController) {
        let pinnedMessageManager = DependenciesBridge.shared.pinnedMessageManager
        let db = DependenciesBridge.shared.db

        let unpinMessage = db.write { tx in
            pinnedMessageManager.getOutgoingUnpinMessage(
                interaction: message,
                thread: thread,
                expiresAt: nil,
                tx: tx,
            )
        }
        guard let unpinMessage else {
            return
        }

        Task {
            await queuePinMessageChangeWithModal(
                message: message,
                pinMessage: unpinMessage,
                modalDelegate: modalDelegate,
                completion: { [weak self] in
                    self?.presentToast(
                        text: OWSLocalizedString(
                            "PINNED_MESSAGE_TOAST",
                            comment: "Text to show on a toast when someone unpins a message",
                        ),
                    )
                },
            )
        }
    }

    public func handleActionUnpinAsync(message: TSMessage) async {
        let pinnedMessageManager = DependenciesBridge.shared.pinnedMessageManager
        let db = DependenciesBridge.shared.db

        let unpinMessage = db.write { tx in
            pinnedMessageManager.getOutgoingUnpinMessage(
                interaction: message,
                thread: thread,
                expiresAt: nil,
                tx: tx,
            )
        }
        guard let unpinMessage else {
            return
        }

        await queuePinMessageChangeWithModal(
            message: message,
            pinMessage: unpinMessage,
            modalDelegate: self,
            completion: nil,
        )
    }

    func messageActionsChangePinStatus(_ itemViewModel: CVItemViewModelImpl, pin: Bool) {
        guard let message = itemViewModel.renderItem.interaction as? TSMessage else {
            return
        }

        if pin {
            handleActionPin(message: message)
            return
        }
        handleActionUnpin(message: message, modalDelegate: self)
    }
}
