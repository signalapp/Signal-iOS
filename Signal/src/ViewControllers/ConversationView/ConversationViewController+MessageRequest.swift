//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices

@objc
extension ConversationViewController: MessageRequestDelegate {

    func messageRequestViewDidTapBlock(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupRequest:
            let blockSheet = createBlockActionSheet()
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

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("GROUPS_INVITE_BLOCK_GROUP",
                                                                         comment: "Label for 'block group' button in group invite view."),
                                                style: .default) { [weak self] _ in
            self?.blockThread()
        })
        let blockInviterTitle = String(format: NSLocalizedString("GROUPS_INVITE_BLOCK_INVITER_FORMAT",
                                                                 comment: "Label for 'block inviter' button in group invite view. Embeds {{name of user who invited you}}."),
                                       addedByName)
        actionSheet.addAction(ActionSheetAction(title: blockInviterTitle,
                                                style: .default) { [weak self] _ in
            self?.blockUserAndDelete(addedByAddress)
        })
        let blockGroupAndInviterTitle = String(format: NSLocalizedString("GROUPS_INVITE_BLOCK_GROUP_AND_INVITER_FORMAT",
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
        blockingManager.addBlockedThread(thread, blockMode: .localShouldLeaveGroups)
        syncManager.sendMessageRequestResponseSyncMessage(thread: thread,
                                                          responseType: .block)
    }

    func blockThreadAndDelete() {
        // Do not leave the group while blocking the thread; we'll
        // that below so that we can surface an error to the user
        // if leaving the group fails.
        blockingManager.addBlockedThread(thread, blockMode: .localShouldNotLeaveGroups)
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .blockAndDelete)
        leaveAndSoftDeleteThread()
    }

    func blockUserAndDelete(_ address: SignalServiceAddress) {
        // Do not leave the group while blocking the thread; we'll
        // that below so that we can surface an error to the user
        // if leaving the group fails.
        blockingManager.addBlockedAddress(address, blockMode: .localShouldNotLeaveGroups)
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
                self.blockingManager.addBlockedGroup(groupThread.groupModel, blockMode: .localShouldNotLeaveGroups, transaction: transaction)
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
        let deleteSheet = createDeleteActionSheet()
        presentActionSheet(deleteSheet)
    }

    func leaveAndSoftDeleteThread() {
        AssertIsOnMainThread()

        let completion = {
            ConversationViewController.databaseStorage.write { transaction in
                self.thread.softDelete(with: transaction)
            }
            self.conversationSplitViewController?.closeSelectedConversation(animated: true)
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
                let profileKeyMessage = OWSProfileKeyMessage(thread: thread)
                SSKEnvironment.shared.messageSenderJobQueue.add(message: profileKeyMessage.asPreparer, transaction: transaction)
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
            message = NSLocalizedString(
                "BLOCK_LIST_UNBLOCK_GROUP_MESSAGE", comment: "An explanation of what unblocking a group means.")
        } else if let contactThread = thread as? TSContactThread {
            threadName = contactsManager.displayName(for: contactThread.contactAddress)
            message = NSLocalizedString(
                "BLOCK_LIST_UNBLOCK_CONTACT_MESSAGE", comment: "An explanation of what unblocking a contact means.")
        } else {
            owsFailDebug("Invalid thread.")
            return
        }

        let title = String(format: NSLocalizedString("BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                                                     comment: "A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."),
                           threadName)

        OWSActionSheets.showConfirmationAlert(
            title: title,
            message: message,
            proceedTitle: NSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON",
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

extension ConversationViewController: MessageRequestNameCollisionDelegate {

    func createBlockActionSheet(sheetCompletion: ((Bool) -> Void)? = nil) -> ActionSheetController {
        Logger.info("")

        let actionSheetTitleFormat: String
        let actionSheetMessage: String
        if thread.isGroupThread {
            actionSheetTitleFormat = NSLocalizedString("MESSAGE_REQUEST_BLOCK_GROUP_TITLE_FORMAT",
                comment: "Action sheet title to confirm blocking a group via a message request. Embeds {{group name}}")
            actionSheetMessage = NSLocalizedString("MESSAGE_REQUEST_BLOCK_GROUP_MESSAGE",
                comment: "Action sheet message to confirm blocking a group via a message request.")
        } else {
            actionSheetTitleFormat = NSLocalizedString("MESSAGE_REQUEST_BLOCK_CONVERSATION_TITLE_FORMAT",
                comment: "Action sheet title to confirm blocking a contact via a message request. Embeds {{contact name or phone number}}")
            actionSheetMessage = NSLocalizedString("MESSAGE_REQUEST_BLOCK_CONVERSATION_MESSAGE",
                comment: "Action sheet message to confirm blocking a conversation via a message request.")
        }

        let threadName = contactsManager.displayNameWithSneakyTransaction(thread: thread)
        let actionSheetTitle = String(format: actionSheetTitleFormat, threadName)
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)

        let blockActionTitle = NSLocalizedString("MESSAGE_REQUEST_BLOCK_ACTION",
            comment: "Action sheet action to confirm blocking a thread via a message request.")
        let blockAndDeleteActionTitle = NSLocalizedString("MESSAGE_REQUEST_BLOCK_AND_DELETE_ACTION",
            comment: "Action sheet action to confirm blocking and deleting a thread via a message request.")

        actionSheet.addAction(ActionSheetAction(title: blockActionTitle) { [weak self] _ in
            self?.blockThread()
            sheetCompletion?(true)
        })
        actionSheet.addAction(ActionSheetAction(title: blockAndDeleteActionTitle) { [weak self] _ in
            self?.blockThreadAndDelete()
            sheetCompletion?(true)
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel, handler: { _ in
            sheetCompletion?(false)
        }))
        return actionSheet
    }

    func createDeleteActionSheet(sheetCompletion: ((Bool) -> Void)? = nil) -> ActionSheetController {
        let actionSheetTitle: String
        let actionSheetMessage: String
        let confirmationText: String

        var isMemberOfGroup = false
        if let groupThread = thread as? TSGroupThread {
            isMemberOfGroup = groupThread.isLocalUserMemberOfAnyKind
        }

        if isMemberOfGroup {
            actionSheetTitle = NSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_TITLE",
                                                 comment: "Action sheet title to confirm deleting a group via a message request.")
            actionSheetMessage = NSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_MESSAGE",
                                                   comment: "Action sheet message to confirm deleting a group via a message request.")
            confirmationText = NSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_ACTION",
                                                  comment: "Action sheet action to confirm deleting a group via a message request.")
        } else { // either 1:1 thread, or a group of which I'm not a member
            actionSheetTitle = NSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_TITLE",
                                                 comment: "Action sheet title to confirm deleting a conversation via a message request.")
            actionSheetMessage = NSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_MESSAGE",
                                                   comment: "Action sheet message to confirm deleting a conversation via a message request.")
            confirmationText = NSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_ACTION",
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

    func nameCollisionController(_ controller: MessageRequestNameCollisionViewController, didResolveCollisionsSuccessfully success: Bool) {
        if success {
            ensureBannerState()
        } else {
            // This may have already been closed (e.g. if the user requested deletion), but
            // it's not guaranteed (e.g. the user blocked the request). Let's close it just
            // to be safe.
            self.conversationSplitViewController?.closeSelectedConversation(animated: false)
        }
        controller.dismiss(animated: true, completion: nil)
    }
}
