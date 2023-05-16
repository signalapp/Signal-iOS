//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalMessaging
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

    func showBlockInviteActionSheet() {
        Logger.info("")

        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }
        let groupMembership = groupThread.groupModel.groupMembership
        guard groupMembership.isInvitedMember(localAddress) else {
            owsFailDebug("Can't reject invite if not pending.")
            return
        }
        guard let addedByUuid = groupMembership.addedByUuid(forInvitedMember: localAddress) else {
            owsFailDebug("Missing addedByUuid.")
            return
        }
        let addedByAddress = SignalServiceAddress(uuid: addedByUuid)
        let addedByName = contactsManager.displayName(for: addedByAddress)

        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("GROUPS_INVITE_BLOCK_GROUP",
                                                                         comment: "Label for 'block group' button in group invite view."),
                                                style: .default) { [weak self] _ in
            self?.blockThread()
        })
        let blockInviterTitle = String(format: OWSLocalizedString("GROUPS_INVITE_BLOCK_INVITER_FORMAT",
                                                                 comment: "Label for 'block inviter' button in group invite view. Embeds {{name of user who invited you}}."),
                                       addedByName)
        actionSheet.addAction(ActionSheetAction(title: blockInviterTitle,
                                                style: .default) { [weak self] _ in
            self?.blockUserAndDelete(addedByAddress)
        })
        let blockGroupAndInviterTitle = String(format: OWSLocalizedString("GROUPS_INVITE_BLOCK_GROUP_AND_INVITER_FORMAT",
                                                                         comment: "Label for 'block group and inviter' button in group invite view. Embeds {{name of user who invited you}}."),
                                               addedByName)
        actionSheet.addAction(ActionSheetAction(title: blockGroupAndInviterTitle,
                                                style: .default) { [weak self] _ in
            self?.blockUserAndGroupAndDelete(addedByAddress)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    func blockThread() {
        // Leave the group while blocking the thread.
        databaseStorage.write { transaction in
            blockingManager.addBlockedThread(thread,
                                             blockMode: .localShouldLeaveGroups,
                                             transaction: transaction)
        }
        syncManager.sendMessageRequestResponseSyncMessage(thread: thread,
                                                          responseType: .block)
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    func blockThreadAndDelete() {
        // Do not leave the group while blocking the thread; we'll
        // that below so that we can surface an error to the user
        // if leaving the group fails.
        databaseStorage.write { transaction in
            blockingManager.addBlockedThread(thread,
                                             blockMode: .localShouldNotLeaveGroups,
                                             transaction: transaction)
        }
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .blockAndDelete)
        leaveAndSoftDeleteThread()
    }

    func blockThreadAndReportSpam() {
        databaseStorage.write { transaction in
            blockingManager.addBlockedThread(thread,
                                             blockMode: .localShouldNotLeaveGroups,
                                             transaction: transaction)
        }
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread, responseType: .block)
        reportSpam()

        presentToastCVC(
            OWSLocalizedString(
                "MESSAGE_REQUEST_SPAM_REPORTED_AND_BLOCKED",
                comment: "String indicating that spam has been reported and the chat has been blocked."
            )
        )
        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    func reportSpam() {
        guard let contactThread = thread as? TSContactThread else {
            return owsFailDebug("Unexpected thread type for reporting spam \(type(of: thread))")
        }

        guard let serviceId = contactThread.contactAddress.serviceId else {
            return owsFailDebug("Missing uuid for reporting spam from \(contactThread.contactAddress)")
        }

        // We only report a selection of the N most recent messages
        // in the conversation.
        let maxMessagesToReport = 3

        let (guidsToReport, reportingToken) = databaseStorage.read { transaction -> ([String], SpamReportingToken?) in
            var guidsToReport = [String]()
            do {
                try InteractionFinder(
                    threadUniqueId: self.thread.uniqueId
                ).enumerateRecentInteractions(
                    transaction: transaction
                ) { interaction, stop in
                    guard let incomingMessage = interaction as? TSIncomingMessage else { return }
                    if let serverGuid = incomingMessage.serverGuid {
                        guidsToReport.append(serverGuid)
                    }
                    guard guidsToReport.count < maxMessagesToReport else {
                        stop.pointee = true
                        return
                    }
                }
            } catch {
                owsFailDebug("Failed to lookup guids to report \(error)")
            }

            var reportingToken: SpamReportingToken?
            do {
                reportingToken = try SpamReportingTokenRecord.reportingToken(
                    for: serviceId,
                    database: transaction.unwrapGrdbRead.database
                )
            } catch {
                owsFailBeta("Failed to look up spam reporting token. Continuing on, as the parameter is optional. Error: \(error)")
            }

            return (guidsToReport, reportingToken)
        }

        guard !guidsToReport.isEmpty else {
            Logger.warn("No messages with serverGuids to report.")
            return
        }

        Logger.info(
            "Reporting \(guidsToReport.count) message(s) from \(serviceId) as spam. We \(reportingToken == nil ? "do not have" : "have") a reporting token"
        )

        var promises = [Promise<Void>]()
        for guid in guidsToReport {
            let request = OWSRequestFactory.reportSpam(
                from: serviceId,
                withServerGuid: guid,
                reportingToken: reportingToken
            )
            promises.append(networkManager.makePromise(request: request).asVoid())
        }

        Promise.when(fulfilled: promises).done {
            Logger.info("Successfully reported \(guidsToReport.count) message(s) from \(serviceId) as spam.")
        }.catch { error in
            owsFailDebug("Failed to report message(s) from \(serviceId) as spam with error: \(error)")
        }
    }

    func blockUserAndDelete(_ address: SignalServiceAddress) {
        // Do not leave the group while blocking the thread; we'll
        // that below so that we can surface an error to the user
        // if leaving the group fails.
        databaseStorage.write { transaction in
            blockingManager.addBlockedAddress(address,
                                              blockMode: .localShouldNotLeaveGroups,
                                              transaction: transaction)
        }
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .delete)
        leaveAndSoftDeleteThread()
    }

    func blockUserAndGroupAndDelete(_ address: SignalServiceAddress) {
        ConversationViewController.databaseStorage.write { transaction in
            if let groupThread = self.thread as? TSGroupThread {
                // Do not leave the group while blocking the thread; we'll
                // that below so that we can surface an error to the user
                // if leaving the group fails.
                self.blockingManager.addBlockedGroup(groupModel: groupThread.groupModel,
                                                     blockMode: .localShouldNotLeaveGroups,
                                                     transaction: transaction)
            } else {
                owsFailDebug("Invalid thread.")
            }
            self.blockingManager.addBlockedAddress(address, blockMode: .localShouldNotLeaveGroups, transaction: transaction)
        }
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .blockAndDelete)
        leaveAndSoftDeleteThread()
    }

    func messageRequestViewDidTapDelete() {
        AssertIsOnMainThread()
        let deleteSheet = createDeleteThreadActionSheet()
        presentActionSheet(deleteSheet)
    }

    func leaveAndSoftDeleteThread() {
        AssertIsOnMainThread()

        let completion = {
            ConversationViewController.databaseStorage.write { transaction in
                self.thread.softDelete(with: transaction)
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

    func messageRequestViewDidTapAccept(mode: MessageRequestMode) {
        messageRequestViewDidTapAccept(mode: mode, unblockThread: false)
    }

    func messageRequestViewDidTapAccept(mode: MessageRequestMode, unblockThread: Bool) {
        AssertIsOnMainThread()

        let thread = self.thread
        let completion = {
            SDSDatabaseStorage.shared.asyncWrite { transaction in
                if unblockThread {
                    self.blockingManager.removeBlockedThread(thread, wasLocallyInitiated: true, transaction: transaction)
                }

                // Whitelist the thread
                self.profileManager.addThread(toProfileWhitelist: thread, transaction: transaction)

                // Send a sync message notifying our other devices the request was accepted
                self.syncManager.sendMessageRequestResponseSyncMessage(
                    thread: thread,
                    responseType: .accept,
                    transaction: transaction
                )

                // Send our profile key to the sender
                let profileKeyMessage = OWSProfileKeyMessage(thread: thread, transaction: transaction)
                Self.sskJobQueues.messageSenderJobQueue.add(message: profileKeyMessage.asPreparer, transaction: transaction)
                NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
            }
        }

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupRequest:
            completion()
        case .groupInviteRequest:
            guard let groupThread = thread as? TSGroupThread else {
                owsFailDebug("Invalid thread.")
                return
            }
            GroupManager.acceptGroupInviteAsync(groupThread, fromViewController: self, success: completion)
        }
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
            threadName = contactsManager.displayName(for: contactThread.contactAddress)
            message = OWSLocalizedString(
                "BLOCK_LIST_UNBLOCK_CONTACT_MESSAGE", comment: "An explanation of what unblocking a contact means.")
        } else {
            owsFailDebug("Invalid thread.")
            return
        }

        let title = String(format: OWSLocalizedString("BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                                                     comment: "A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."),
                           threadName)

        OWSActionSheets.showConfirmationAlert(
            title: title,
            message: message,
            proceedTitle: OWSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON",
                                            comment: "Button label for the 'unblock' button")
        ) { _ in
            self.messageRequestViewDidTapAccept(mode: mode, unblockThread: true)
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

extension ConversationViewController: NameCollisionResolutionDelegate {

    func createBlockThreadActionSheet(sheetCompletion: ((Bool) -> Void)? = nil) -> ActionSheetController {
        Logger.info("")

        let actionSheetTitleFormat: String
        let actionSheetMessage: String
        if thread.isGroupThread {
            actionSheetTitleFormat = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_GROUP_TITLE_FORMAT",
                                                       comment: "Action sheet title to confirm blocking a group via a message request. Embeds {{group name}}")
            actionSheetMessage = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_GROUP_MESSAGE",
                                                   comment: "Action sheet message to confirm blocking a group via a message request.")
        } else {
            actionSheetTitleFormat = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_CONVERSATION_TITLE_FORMAT",
                                                       comment: "Action sheet title to confirm blocking a contact via a message request. Embeds {{contact name or phone number}}")
            actionSheetMessage = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_CONVERSATION_MESSAGE",
                                                   comment: "Action sheet message to confirm blocking a conversation via a message request.")
        }

        let threadName = contactsManager.displayNameWithSneakyTransaction(thread: thread)
        let actionSheetTitle = String(format: actionSheetTitleFormat, threadName)
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)

        let blockActionTitle = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_ACTION",
                                                 comment: "Action sheet action to confirm blocking a thread via a message request.")
        let blockAndDeleteActionTitle = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_AND_DELETE_ACTION",
                                                          comment: "Action sheet action to confirm blocking and deleting a thread via a message request.")
        let blockAndReportSpamActionTitle = OWSLocalizedString("MESSAGE_REQUEST_BLOCK_AND_REPORT_SPAM_ACTION",
                                                              comment: "Action sheet action to confirm blocking and report spam for a thread via a message request.")

        actionSheet.addAction(ActionSheetAction(title: blockActionTitle) { [weak self] _ in
            self?.blockThread()
            sheetCompletion?(true)
        })
        if thread.isGroupThread {
            actionSheet.addAction(ActionSheetAction(title: blockAndDeleteActionTitle) { [weak self] _ in
                self?.blockThreadAndDelete()
                sheetCompletion?(true)
            })
        } else {
            actionSheet.addAction(ActionSheetAction(title: blockAndReportSpamActionTitle) { [weak self] _ in
                self?.blockThreadAndReportSpam()
                sheetCompletion?(true)
            })
        }

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel, handler: { _ in
            sheetCompletion?(false)
        }))
        return actionSheet
    }

    func createDeleteThreadActionSheet(sheetCompletion: ((Bool) -> Void)? = nil) -> ActionSheetController {
        let actionSheetTitle: String
        let actionSheetMessage: String
        let confirmationText: String

        var isMemberOfGroup = false
        if let groupThread = thread as? TSGroupThread {
            isMemberOfGroup = groupThread.isLocalUserMemberOfAnyKind
        }

        if isMemberOfGroup {
            actionSheetTitle = OWSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_TITLE",
                                                 comment: "Action sheet title to confirm deleting a group via a message request.")
            actionSheetMessage = OWSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_MESSAGE",
                                                   comment: "Action sheet message to confirm deleting a group via a message request.")
            confirmationText = OWSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_ACTION",
                                                 comment: "Action sheet action to confirm deleting a group via a message request.")
        } else { // either 1:1 thread, or a group of which I'm not a member
            actionSheetTitle = OWSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_TITLE",
                                                 comment: "Action sheet title to confirm deleting a conversation via a message request.")
            actionSheetMessage = OWSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_MESSAGE",
                                                   comment: "Action sheet message to confirm deleting a conversation via a message request.")
            confirmationText = OWSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_ACTION",
                                                 comment: "Action sheet action to confirm deleting a conversation via a message request.")
        }

        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(ActionSheetAction(title: confirmationText, handler: { _ in
            self.syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                                   responseType: .delete)
            self.leaveAndSoftDeleteThread()
            sheetCompletion?(true)
        }))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel, handler: { _ in
            sheetCompletion?(false)
        }))
        return actionSheet
    }

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
