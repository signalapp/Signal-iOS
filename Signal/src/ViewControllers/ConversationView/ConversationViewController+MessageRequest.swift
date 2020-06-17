//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices

@objc
extension ConversationViewController: MessageRequestDelegate {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    private var blockingManager: OWSBlockingManager {
        return .shared()
    }

    private var profileManager: OWSProfileManager {
        return .shared()
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var contactManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: -

    func messageRequestViewDidTapBlock(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupV1:
            showBlockContactOrGroupV1ActionSheet()
        case .groupV2:
            showBlockInviteActionSheet()
        }
    }

    func showBlockContactOrGroupV1ActionSheet() {
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

        let blockAction = ActionSheetAction(title: NSLocalizedString("MESSAGE_REQUEST_BLOCK_ACTION",
                                                                     comment: "Action sheet action to confirm blocking a thread via a message request.")) { _ in
                                                                        self.blockingManager.addBlockedThread(self.thread, wasLocallyInitiated: true)
                                                                        self.syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                                                                                               responseType: .block)
        }
        actionSheet.addAction(blockAction)

        let blockAndDeleteAction = ActionSheetAction(title: NSLocalizedString("MESSAGE_REQUEST_BLOCK_AND_DELETE_ACTION",
                                                                              comment: "Action sheet action to confirm blocking and deleting a thread via a message request.")) { _ in
                                                                                self.blockingManager.addBlockedThread(self.thread, wasLocallyInitiated: true)
                                                                                self.syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                                                                                                       responseType: .blockAndDelete)
                                                                                self.leaveAndSoftDeleteThread()
        }
        actionSheet.addAction(blockAndDeleteAction)

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
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
        guard groupMembership.isPending(localAddress) else {
            owsFailDebug("Can't reject invite if not pending.")
            return
        }
        guard let addedByUuid = groupMembership.addedByUuid(forPendingMember: localAddress) else {
            owsFailDebug("Missing addedByUuid.")
            return
        }
        let addedByAddress = SignalServiceAddress(uuid: addedByUuid)
        let addedByName = contactManager.displayName(for: addedByAddress)

        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("GROUPS_INVITE_BLOCK_GROUP",
                                                                         comment: "Label for 'block group' button in group invite view."),
                                                style: .default) { [weak self] _ in
                                                    self?.blockThreadAndDelete()
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

    func blockThreadAndDelete() {
        blockingManager.addBlockedThread(thread, wasLocallyInitiated: true)
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .blockAndDelete)
        leaveAndSoftDeleteThread()
    }

    func blockUserAndDelete(_ address: SignalServiceAddress) {
        blockingManager.addBlockedAddress(address, wasLocallyInitiated: true)
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .delete)
        leaveAndSoftDeleteThread()
    }

    func blockUserAndGroupAndDelete(_ address: SignalServiceAddress) {
        ConversationViewController.databaseStorage.write { transaction in
            if let groupThread = self.thread as? TSGroupThread {
                self.blockingManager.addBlockedGroup(groupThread.groupModel, wasLocallyInitiated: true, transaction: transaction)
            } else {
                owsFailDebug("Invalid thread.")
            }
            self.blockingManager.addBlockedAddress(address, wasLocallyInitiated: true, transaction: transaction)
        }
        syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                          responseType: .blockAndDelete)
        leaveAndSoftDeleteThread()
    }

    func messageRequestViewDidTapDelete() {
        AssertIsOnMainThread()

        let actionSheetTitle: String
        let actionSheetMessage: String
        let actionSheetAction: String

        var isMemberOfGroup = false
        if let groupThread = thread as? TSGroupThread {
            isMemberOfGroup = groupThread.isLocalUserInGroup
        }

        if isMemberOfGroup {
            actionSheetTitle = NSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_TITLE",
                                                 comment: "Action sheet title to confirm deleting a group via a message request.")
            actionSheetMessage = NSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_MESSAGE",
                                                    comment: "Action sheet message to confirm deleting a group via a message request.")
            actionSheetAction = NSLocalizedString("MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_ACTION",
                                                   comment: "Action sheet action to confirm deleting a group via a message request.")
        } else { // either 1:1 thread, or a group of which I'm not a member
            actionSheetTitle = NSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_TITLE",
                                                 comment: "Action sheet title to confirm deleting a conversation via a message request.")
            actionSheetMessage = NSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_MESSAGE",
                                                   comment: "Action sheet message to confirm deleting a conversation via a message request.")
            actionSheetAction = NSLocalizedString("MESSAGE_REQUEST_DELETE_CONVERSATION_ACTION",
                                                  comment: "Action sheet action to confirm deleting a conversation via a message request.")
        }

        OWSActionSheets.showConfirmationAlert(title: actionSheetTitle,
                                              message: actionSheetMessage,
                                              proceedTitle: actionSheetAction) { _ in
                                                self.syncManager.sendMessageRequestResponseSyncMessage(thread: self.thread,
                                                                                                       responseType: .delete)
                                                self.leaveAndSoftDeleteThread()
        }
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
            groupThread.isLocalUserPendingOrNonPendingMember else {
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

        let completion = {
            SDSDatabaseStorage.shared.asyncWrite { transaction in
                if unblockThread {
                    self.blockingManager.removeBlockedThread(self.thread, wasLocallyInitiated: true, transaction: transaction)
                }

                // Whitelist the thread
                self.profileManager.addThread(toProfileWhitelist: self.thread, transaction: transaction)

                // Send a sync message notifying our other devices the request was accepted
                self.syncManager.sendMessageRequestResponseSyncMessage(
                    thread: self.thread,
                    responseType: .accept,
                    transaction: transaction
                )

                // Send our profile key to the sender
                let profileKeyMessage = OWSProfileKeyMessage(thread: self.thread)
                SSKEnvironment.shared.messageSenderJobQueue.add(message: profileKeyMessage.asPreparer, transaction: transaction)

                transaction.addAsyncCompletion {
                    self.dismissMessageRequestView()
                }
            }
        }

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupV1:
            completion()
        case .groupV2:
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
