//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SafariServices
import SignalServiceKit
import SignalUI

extension ConversationViewController: MessageRequestDelegate {
    func messageRequestViewDidTapBlock(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupRequest:
            let blockSheet = createBlockThreadActionSheet()
            presentActionSheet(blockSheet)
        case .groupInviteRequest:
            showBlockInviteActionSheet()
        }
    }

    func messageRequestViewDidTapReport() {
        AssertIsOnMainThread()

        let reportSheet = createReportThreadActionSheet()
        presentActionSheet(reportSheet)
    }

    func messageRequestViewDidTapAccept(mode: MessageRequestMode, unblockThread: Bool, unhideRecipient: Bool) {
        AssertIsOnMainThread()

        let thread = self.thread
        Task {
            await self.acceptMessageRequest(in: thread, mode: mode, unblockThread: unblockThread, unhideRecipient: unhideRecipient)
        }
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
                "BLOCK_LIST_UNBLOCK_GROUP_MESSAGE", comment: "An explanation of what unblocking a group means.")
        } else if let contactThread = thread as? TSContactThread {
            threadName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
            }
            message = OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_CONTACT_MESSAGE",
                comment: "An explanation of what unblocking a contact means."
            )
        } else {
            owsFailDebug("Invalid thread.")
            return
        }

        let title = String(
            format: OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                comment: "A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."
            ),
            threadName
        )

        OWSActionSheets.showConfirmationAlert(
            title: title,
            message: message,
            proceedTitle: OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_BUTTON",
                comment: "Button label for the 'unblock' button"
            )
        ) { _ in
            self.messageRequestViewDidTapAccept(mode: mode, unblockThread: true, unhideRecipient: true)
        }
    }

    func messageRequestViewDidTapLearnMore() {
        AssertIsOnMainThread()

        // TODO Message Request: Use right support url. Right now this just links to the profiles FAQ
        guard let url = URL(string: "https://support.signal.org/hc/articles/360007459591") else {
            return owsFailDebug("Invalid url.")
        }
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }
}

private extension ConversationViewController {
    func blockThread() {
        // Leave the group while blocking the thread.
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(thread,
                                             blockMode: .localShouldLeaveGroups,
                                             transaction: transaction)
        }
        SSKEnvironment.shared.syncManagerRef.sendMessageRequestResponseSyncMessage(thread: thread, responseType: .block)
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    func blockThreadAndDelete() {
        // Do not leave the group while blocking the thread; we'll
        // that below so that we can surface an error to the user
        // if leaving the group fails.
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(thread,
                                             blockMode: .localShouldNotLeaveGroups,
                                             transaction: transaction)
        }
        leaveAndSoftDeleteThread(messageRequestResponseType: .blockAndDelete)
    }

    func blockThreadAndReportSpam(in thread: TSThread) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            ReportSpamUIUtils.blockAndReport(in: thread, tx: tx)
        }

        presentToastCVC(
            OWSLocalizedString(
                "MESSAGE_REQUEST_SPAM_REPORTED_AND_BLOCKED",
                comment: "String indicating that spam has been reported and the chat has been blocked."
            )
        )
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    func reportSpamInThread() {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            ReportSpamUIUtils.report(in: thread, tx: tx)
        }

        presentToastCVC(
            OWSLocalizedString(
                "MESSAGE_REQUEST_SPAM_REPORTED",
                comment: "String indicating that spam has been reported."
            )
        )
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    func blockUserAndDelete(_ aci: Aci) {
        // Do not leave the group while blocking the thread; we'll
        // that below so that we can surface an error to the user
        // if leaving the group fails.
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.blockingManagerRef.addBlockedAci(
                aci,
                blockMode: .localShouldNotLeaveGroups,
                tx: transaction.asV2Write
            )
        }
        leaveAndSoftDeleteThread(messageRequestResponseType: .delete)
    }

    func blockUserAndGroupAndDelete(_ aci: Aci) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            if let groupThread = self.thread as? TSGroupThread {
                // Do not leave the group while blocking the thread; we'll
                // that below so that we can surface an error to the user
                // if leaving the group fails.
                SSKEnvironment.shared.blockingManagerRef.addBlockedGroup(
                    groupModel: groupThread.groupModel,
                    blockMode: .localShouldNotLeaveGroups,
                    transaction: transaction
                )
            } else {
                owsFailDebug("Invalid thread.")
            }
            SSKEnvironment.shared.blockingManagerRef.addBlockedAci(
                aci,
                blockMode: .localShouldNotLeaveGroups,
                tx: transaction.asV2Write
            )
        }
        leaveAndSoftDeleteThread(messageRequestResponseType: .blockAndDelete)
    }

    func leaveAndSoftDeleteThread(
        messageRequestResponseType: OWSSyncMessageRequestResponseType
    ) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.syncManagerRef.sendMessageRequestResponseSyncMessage(
            thread: self.thread,
            responseType: messageRequestResponseType
        )

        let completion = {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                DependenciesBridge.shared.threadSoftDeleteManager.softDelete(
                    threads: [self.thread],
                    // We're already sending a sync message about this above!
                    sendDeleteForMeSyncMessage: false,
                    tx: transaction.asV2Write
                )
            }
            self.conversationSplitViewController?.closeSelectedConversation(animated: true)
            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        }

        guard let groupThread = thread as? TSGroupThread,
              groupThread.isLocalUserFullOrInvitedMember else {
            // If we don't need to leave the group, finish up immediately.
            return completion()
        }

        // Leave the group if we're a member.
        GroupManager.leaveGroupOrDeclineInviteAsyncWithUI(groupThread: groupThread, fromViewController: self, success: completion)
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
        unhideRecipient: Bool
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
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            if unblockThread {
                SSKEnvironment.shared.blockingManagerRef.removeBlockedThread(
                    thread,
                    wasLocallyInitiated: true,
                    transaction: transaction
                )
            }

            if unhideRecipient, let thread = thread as? TSContactThread {
                do {
                    try DependenciesBridge.shared.recipientHidingManager.removeHiddenRecipient(
                        thread.contactAddress,
                        wasLocallyInitiated: true,
                        tx: transaction.asV2Write
                    )
                } catch {
                    owsFailDebug("Couldn't unhide recipient")
                }
            }

            /// If we're not in "unblock" mode, we should take "accept message
            /// request" actions. (Bleh.)
            if !unblockThread {
                /// Insert an info message indicating that we accepted.
                DependenciesBridge.shared.interactionStore.insertInteraction(
                    TSInfoMessage(
                        thread: thread,
                        messageType: .acceptedMessageRequest
                    ),
                    tx: transaction.asV2Write
                )

                /// Send a sync message telling our other devices that we
                /// accepted.
                SSKEnvironment.shared.syncManagerRef.sendMessageRequestResponseSyncMessage(
                    thread: thread,
                    responseType: .accept,
                    transaction: transaction
                )
            }

            // Whitelist the thread
            SSKEnvironment.shared.profileManagerRef.addThread(
                toProfileWhitelist: thread,
                userProfileWriter: .localUser,
                transaction: transaction
            )

            if !thread.isGroupThread {
                // If this is a contact thread, we should give the
                // now-unblocked contact our profile key.
                let profileKeyMessage = OWSProfileKeyMessage(thread: thread, transaction: transaction)
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: profileKeyMessage
                )
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
            }

            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        }
    }
}

// MARK: - Action Sheets

extension ConversationViewController {

    func showBlockInviteActionSheet() {
        Logger.info("")

        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            owsFailDebug("Missing local identifiers!")
            return
        }

        let groupMembership = groupThread.groupModel.groupMembership

        guard let invitedAtServiceId = groupMembership.localUserInvitedAtServiceId(
            localIdentifiers: localIdentifiers
        ) else {
            owsFailDebug("Can't reject invite if not invited!")
            return
        }

        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUPS_INVITE_BLOCK_GROUP",
                comment: "Label for 'block group' button in group invite view."
            ),
            style: .default
        ) { [weak self] _ in
            self?.blockThread()
        })

        if let addedByAci = groupMembership.addedByAci(forInvitedMember: invitedAtServiceId) {
            let addedByName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(addedByAci), tx: tx).resolvedValue()
            }

            actionSheet.addAction(ActionSheetAction(
                title: String(
                    format: OWSLocalizedString(
                        "GROUPS_INVITE_BLOCK_INVITER_FORMAT",
                        comment: "Label for 'block inviter' button in group invite view. Embeds {{name of user who invited you}}."
                    ),
                    addedByName
                ),
                style: .default
            ) { [weak self] _ in
                self?.blockUserAndDelete(addedByAci)
            })

            actionSheet.addAction(ActionSheetAction(
                title: String(
                    format: OWSLocalizedString(
                        "GROUPS_INVITE_BLOCK_GROUP_AND_INVITER_FORMAT",
                        comment: "Label for 'block group and inviter' button in group invite view. Embeds {{name of user who invited you}}."),
                    addedByName
                ),
                style: .default
            ) { [weak self] _ in
                self?.blockUserAndGroupAndDelete(addedByAci)
            })
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    func createBlockThreadActionSheet(sheetCompletion: ((Bool) -> Void)? = nil) -> ActionSheetController {
        Logger.info("")

        let actionSheetTitleFormat: String
        let actionSheetMessage: String
        if thread.isGroupThread {
            actionSheetTitleFormat = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_GROUP_TITLE_FORMAT",
                comment: "Action sheet title to confirm blocking a group via a message request. Embeds {{group name}}"
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_GROUP_MESSAGE",
                comment: "Action sheet message to confirm blocking a group via a message request."
            )
        } else {
            actionSheetTitleFormat = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_CONVERSATION_TITLE_FORMAT",
                comment: "Action sheet title to confirm blocking a contact via a message request. Embeds {{contact name or phone number}}"
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_BLOCK_CONVERSATION_MESSAGE",
                comment: "Action sheet message to confirm blocking a conversation via a message request."
            )
        }

        let (threadName, hasReportedSpam) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let threadName = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
            let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
            let hasReportedSpam = finder.hasUserReportedSpam(transaction: tx)
            return (threadName, hasReportedSpam)
        }
        let actionSheetTitle = String(format: actionSheetTitleFormat, threadName)
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)

        let blockActionTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_BLOCK_ACTION",
            comment: "Action sheet action to confirm blocking a thread via a message request."
        )
        let blockAndDeleteActionTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_BLOCK_AND_DELETE_ACTION",
            comment: "Action sheet action to confirm blocking and deleting a thread via a message request."
        )
        let blockAndReportSpamActionTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_BLOCK_AND_REPORT_SPAM_ACTION",
            comment: "Action sheet action to confirm blocking and reporting spam for a thread via a message request."
        )

        actionSheet.addAction(ActionSheetAction(title: blockActionTitle) { [weak self] _ in
            self?.blockThread()
            sheetCompletion?(true)
        })

        if !hasReportedSpam {
            actionSheet.addAction(ActionSheetAction(title: blockAndReportSpamActionTitle) { [weak self] _ in
                guard let self else { return }
                self.blockThreadAndReportSpam(in: self.thread)
                sheetCompletion?(true)
            })
        } else {
            actionSheet.addAction(ActionSheetAction(title: blockAndDeleteActionTitle) { [weak self] _ in
                self?.blockThreadAndDelete()
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
            isMemberOfGroup = groupThread.isLocalUserMemberOfAnyKind
        }

        if isMemberOfGroup {
            actionSheetTitle = OWSLocalizedString(
                "MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_TITLE",
                comment: "Action sheet title to confirm deleting a group via a message request."
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_MESSAGE",
                comment: "Action sheet message to confirm deleting a group via a message request."
            )
            confirmationText = OWSLocalizedString(
                "MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_ACTION",
                comment: "Action sheet action to confirm deleting a group via a message request."
            )
        } else { // either 1:1 thread, or a group of which I'm not a member
            actionSheetTitle = OWSLocalizedString(
                "MESSAGE_REQUEST_DELETE_CONVERSATION_TITLE",
                comment: "Action sheet title to confirm deleting a conversation via a message request."
            )
            actionSheetMessage = OWSLocalizedString(
                "MESSAGE_REQUEST_DELETE_CONVERSATION_MESSAGE",
                comment: "Action sheet message to confirm deleting a conversation via a message request."
            )
            confirmationText = OWSLocalizedString(
                "MESSAGE_REQUEST_DELETE_CONVERSATION_ACTION",
                comment: "Action sheet action to confirm deleting a conversation via a message request."
            )
        }

        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(ActionSheetAction(title: confirmationText, handler: { _ in
            self.leaveAndSoftDeleteThread(messageRequestResponseType: .delete)
        }))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel))
        return actionSheet
    }

    // TODO[SPAM]: For groups, fetch the inviter to add to the message
    func createReportThreadActionSheet() -> ActionSheetController {
        return ReportSpamUIUtils.createReportSpamActionSheet(
            for: thread,
            isBlocked: threadViewModel.isBlocked
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
