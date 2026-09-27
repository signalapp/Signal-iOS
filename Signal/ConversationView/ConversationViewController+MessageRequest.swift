//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SafariServices
import SignalServiceKit
import SignalUI

extension ConversationViewController: MessageRequestDelegate {
    func messageRequestViewDidTapBlock() {
        AssertIsOnMainThread()

        let blockSheet = createBlockThreadActionSheet()
        presentActionSheet(blockSheet)
    }

    func messageRequestViewDidTapReport() {
        AssertIsOnMainThread()

        let reportSheet = createReportThreadActionSheet()
        presentActionSheet(reportSheet)
    }

    func messageRequestViewDidTapAccept(mode: MessageRequestMode, unblockThread: Bool, unhideRecipient: Bool) {
        AssertIsOnMainThread()

        let messageFormat = OWSLocalizedString(
            "MESSAGE_REQUEST_CONFIRM_ACCEPT_MESSAGE",
            comment: "Message for an action sheet asking the user to confirm if they want to accept a message request. {{ Embeds 'Signal will never' in bolded text }}",
        )

        let embeddedMessage = OWSLocalizedString(
            "MESSAGE_REQUEST_CONFIRM_ACCEPT_MESSAGE_EMBEDDED_BOLD_TEXT",
            comment: "Embedded text in the message for an action sheet asking the user to confirm if they want to accept a message request.",
        )

        let message = NSAttributedString.make(
            fromFormat: messageFormat,
            attributedFormatArgs: [
                .string(
                    embeddedMessage,
                    attributes: [
                        .foregroundColor: UIColor.Signal.label,
                        .font: UIFont.dynamicTypeBody.semibold(),
                    ],
                ),
            ],
            defaultAttributes: [
                .foregroundColor: UIColor.Signal.label,
                .font: UIFont.dynamicTypeBody,
            ],
        )

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("MESSAGE_REQUEST_CONFIRM_ACCEPT_TITLE", comment: "Title for an action sheet asking the user to confirm if they want to accept a message request"),
            message: message,
            proceedTitle: OWSLocalizedString(
                "MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
                comment: "A button used to accept a user on an incoming message request.",
            ),
            proceedAction: { _ in
                let thread = self.thread
                Task {
                    await self.acceptMessageRequest(in: thread, mode: mode, unblockThread: unblockThread, unhideRecipient: unhideRecipient)
                }
            },
        )
    }

    func messageRequestViewDidTapDelete() {
        AssertIsOnMainThread()

        let deleteSheet = createDeleteThreadActionSheet()
        presentActionSheet(deleteSheet)
    }

    func messageRequestViewDidTapUnblock(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        let threadName: String
        let message: String
        if let groupThread = thread as? TSGroupThread {
            threadName = groupThread.groupNameOrDefault
            message = OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_GROUP_MESSAGE",
                comment: "An explanation of what unblocking a group means.",
            )
        } else if let contactThread = thread as? TSContactThread {
            threadName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
            }
            message = OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_CONTACT_MESSAGE",
                comment: "An explanation of what unblocking a contact means.",
            )
        } else {
            owsFailDebug("Invalid thread.")
            return
        }

        let title = String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                comment: "A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}.",
            ),
            threadName,
        )

        OWSActionSheets.showConfirmationAlert(
            title: title,
            message: message,
            proceedTitle: OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_BUTTON",
                comment: "Button label for the 'unblock' button",
            ),
        ) { _ in
            self.messageRequestViewDidTapAccept(mode: mode, unblockThread: true, unhideRecipient: true)
        }
    }

    func messageRequestViewDidTapLearnMore() {
        AssertIsOnMainThread()

        let safariVC = SFSafariViewController(url: URL.Support.profilesAndMessageRequests)
        present(safariVC, animated: true)
    }
}

private extension ConversationViewController {
    func declineMessageRequest(responseType: OutgoingMessageRequestResponseSyncMessage.ResponseType) {
        MessageRequestDecliner.declineMessageRequest(
            inThread: self.thread,
            responseType: responseType,
        )
        if responseType.shouldDeleteThread {
            self.conversationSplitViewController?.closeSelectedConversation(animated: true)
        }
        if responseType.shouldReportSpam {
            self.presentToastCVC(
                ReportSpamUIUtils.successfulReportText(didBlock: responseType.shouldBlockThread),
            )
        }
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    /// Accept a message request, or unblock chat.
    ///
    /// It's not obvious, but the "message request" UI is shown when a chat is
    /// blocked. However, the "blocked chat" UI only has the option to delete a
    /// chat or unblock. If the user selects "unblock", we end up here with
    /// `unblockThread: true`.
    func acceptMessageRequest(
        in thread: TSThread,
        mode: MessageRequestMode,
        unblockThread: Bool,
        unhideRecipient: Bool,
    ) async {
        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
            return
        case .contactOrGroupRequest:
            break
        case .groupInviteRequest:
            guard let groupThread = thread as? TSGroupThread else {
                owsFailDebug("Invalid thread.")
                return
            }
            do {
                try await GroupManager.acceptGroupInviteWithModal(groupThread, fromViewController: self)
            } catch {
                owsFailDebug("Couldn't accept group invite: \(error)")
                return
            }
        }

        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let hidingManager = DependenciesBridge.shared.recipientHidingManager
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        func unblockThreadIfNeeded(transaction: DBWriteTransaction) {
            if unblockThread {
                blockingManager.removeBlockedThread(
                    thread,
                    wasLocallyInitiated: true,
                    transaction: transaction,
                )
            }
        }

        func acceptMessageRequestIfNeeded(transaction: DBWriteTransaction) {
            /// If we're not in "unblock" mode, we should take "accept message
            /// request" actions. (Bleh.)
            if !unblockThread {
                /// Insert an info message indicating that we accepted.
                DependenciesBridge.shared.interactionStore.insertInteraction(
                    TSInfoMessage(
                        thread: thread,
                        messageType: .acceptedMessageRequest,
                    ),
                    tx: transaction,
                )

                /// Send a sync message telling our other devices that we
                /// accepted.
                SSKEnvironment.shared.syncManagerRef.sendMessageRequestResponseSyncMessage(
                    thread: thread,
                    responseType: .accept,
                    transaction: transaction,
                )
            }
        }

        await databaseStorage.awaitableWrite { transaction in
            switch thread {
            case let thread as TSGroupThread:
                unblockThreadIfNeeded(transaction: transaction)
                acceptMessageRequestIfNeeded(transaction: transaction)
                profileManager.addGroupId(
                    toProfileWhitelist: thread.groupModel.groupId,
                    userProfileWriter: .localUser,
                    transaction: transaction,
                )

            case let thread as TSContactThread:
                unblockThreadIfNeeded(transaction: transaction)
                // Might be nil if thread.contactAddress isn't valid.
                var recipient = recipientFetcher.fetchOrCreate(address: thread.contactAddress, tx: transaction)
                if var innerRecipient = recipient {
                    if unhideRecipient, !thread.contactAddress.isLocalAddress {
                        hidingManager.removeHiddenRecipient(&innerRecipient, wasLocallyInitiated: true, tx: transaction)
                    }
                    recipient = innerRecipient
                }
                acceptMessageRequestIfNeeded(transaction: transaction)
                if var innerRecipient = recipient {
                    profileManager.addRecipientToProfileWhitelist(&innerRecipient, userProfileWriter: .localUser, tx: transaction)
                    recipient = innerRecipient
                }
                // If this is a contact thread, we should give the
                // now-unblocked contact our profile key.
                let profileKeyMessage = ProfileKeyMessage(
                    thread: thread,
                    profileKey: profileManager.localProfileKey(tx: transaction)!,
                    tx: transaction,
                )
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: profileKeyMessage,
                )
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)

            default:
                owsFailDebug("can't accept message request for \(type(of: thread))")
            }

            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        }
    }
}

// MARK: - Action Sheets

extension ConversationViewController {

    func createBlockThreadActionSheet(sheetCompletion: ((Bool) -> Void)? = nil) -> ActionSheetController {
        Logger.info("")

        let actionSheetTitleFormat: String
        let actionSheetMessage: String
        if thread.isGroupThread {
            actionSheetTitleFormat = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_GROUP_TITLE_FORMAT",
                comment: "Action sheet title to confirm blocking a group via a message request. Embeds {{group name}}",
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_GROUP_MESSAGE",
                comment: "Action sheet message to confirm blocking a group via a message request.",
            )
        } else {
            actionSheetTitleFormat = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_CONVERSATION_TITLE_FORMAT",
                comment: "Action sheet title to confirm blocking a contact via a message request. Embeds {{contact name or phone number}}",
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_CONVERSATION_MESSAGE",
                comment: "Action sheet message to confirm blocking a conversation via a message request.",
            )
        }

        let (threadName, hasReportedSpam) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let threadName = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
            let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
            let hasReportedSpam = finder.hasUserReportedSpam(transaction: tx)
            return (threadName, hasReportedSpam)
        }
        let actionSheetTitle = String.nonPluralLocalizedStringWithFormat(actionSheetTitleFormat, threadName)
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)

        let blockActionTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_BLOCK_ACTION",
            comment: "Action sheet action to confirm blocking a thread via a message request.",
        )
        let blockAndDeleteActionTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_BLOCK_AND_DELETE_ACTION",
            comment: "Action sheet action to confirm blocking and deleting a thread via a message request.",
        )
        let blockAndReportSpamActionTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_BLOCK_AND_REPORT_SPAM_ACTION",
            comment: "Action sheet action to confirm blocking and reporting spam for a thread via a message request.",
        )

        actionSheet.addAction(ActionSheetAction(title: blockActionTitle) { [weak self] _ in
            self?.declineMessageRequest(responseType: .block)
            sheetCompletion?(true)
        })

        if !hasReportedSpam {
            actionSheet.addAction(ActionSheetAction(title: blockAndReportSpamActionTitle) { [weak self] _ in
                self?.declineMessageRequest(responseType: .blockAndSpam)
                sheetCompletion?(true)
            })
        } else {
            actionSheet.addAction(ActionSheetAction(title: blockAndDeleteActionTitle) { [weak self] _ in
                self?.declineMessageRequest(responseType: .blockAndDelete)
                sheetCompletion?(true)
            })
        }

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel, handler: { _ in
            sheetCompletion?(false)
        }))
        return actionSheet
    }

    func createDeleteThreadActionSheet() -> ActionSheetController {
        let actionSheetTitle: String
        let actionSheetMessage: String
        let confirmationText: String

        var isMemberOfGroup = false
        if let groupThread = thread as? TSGroupThread {
            isMemberOfGroup = groupThread.groupModel.groupMembership.isLocalUserMemberOfAnyKind
        }

        if isMemberOfGroup {
            actionSheetTitle = OWSLocalizedString(
                "MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_TITLE",
                comment: "Action sheet title to confirm deleting a group via a message request.",
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_MESSAGE",
                comment: "Action sheet message to confirm deleting a group via a message request.",
            )
            confirmationText = OWSLocalizedString(
                "MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_ACTION",
                comment: "Action sheet action to confirm deleting a group via a message request.",
            )
        } else { // either 1:1 thread, or a group of which I'm not a member
            actionSheetTitle = OWSLocalizedString(
                "MESSAGE_REQUEST_DELETE_CONVERSATION_TITLE",
                comment: "Action sheet title to confirm deleting a conversation via a message request.",
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_DELETE_CONVERSATION_MESSAGE",
                comment: "Action sheet message to confirm deleting a conversation via a message request.",
            )
            confirmationText = OWSLocalizedString(
                "MESSAGE_REQUEST_DELETE_CONVERSATION_ACTION",
                comment: "Action sheet action to confirm deleting a conversation via a message request.",
            )
        }

        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(ActionSheetAction(title: confirmationText, handler: { [weak self] _ in
            self?.declineMessageRequest(responseType: .delete)
        }))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel))
        return actionSheet
    }

    // TODO[SPAM]: For groups, fetch the inviter to add to the message
    func createReportThreadActionSheet() -> ActionSheetController {
        return ReportSpamUIUtils.createReportSpamActionSheet(
            forThread: thread,
            isBlocked: threadViewModel.isBlocked,
            declineMessageRequest: self.declineMessageRequest(responseType:),
        )
    }
}

extension ConversationViewController: NameCollisionResolutionDelegate {

    func nameCollisionControllerDidComplete(_ controller: NameCollisionResolutionViewController, dismissConversationView: Bool) {
        if dismissConversationView {
            // This may have already been closed (e.g. if the user requested deletion), but
            // it's not guaranteed (e.g. the user blocked the request). Let's close it just
            // to be safe.
            self.conversationSplitViewController?.closeSelectedConversation(animated: false)
        } else {
            // Conversation view is being kept around. Update the banner state to account for any changes
            ensureBannerState()
        }
        controller.dismiss(animated: true, completion: nil)
    }
}
