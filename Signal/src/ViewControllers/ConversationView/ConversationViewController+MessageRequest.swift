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

    // MARK: -

    func messageRequestViewDidTapBlock(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupV1:
            blockThreadAndDelete()
        case .groupV2:
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
        leaveAndSoftDeleteThread()
    }

    func blockUserAndDelete(_ address: SignalServiceAddress) {
        blockingManager.addBlockedAddress(address, wasLocallyInitiated: true)
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
        leaveAndSoftDeleteThread()
    }

    func messageRequestViewDidTapDelete() {
        AssertIsOnMainThread()

        leaveAndSoftDeleteThread()
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
        ThreadUtil.leaveGroupOrDeclineInviteAsync(groupThread, fromViewController: self, success: completion)
    }

    func messageRequestViewDidTapAccept(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        let completion = {
            self.profileManager.addThread(toProfileWhitelist: self.thread)
            self.dismissMessageRequestView()
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
            ThreadUtil.acceptGroupInviteAsync(groupThread, fromViewController: self, success: completion)
        }
    }

    func messageRequestViewDidTapUnblock(mode: MessageRequestMode) {
        AssertIsOnMainThread()

        blockingManager.removeBlockedThread(thread, wasLocallyInitiated: true)
        messageRequestViewDidTapAccept(mode: mode)
    }

    func messageRequestViewDidTapLearnMore() {
        AssertIsOnMainThread()

        // TODO Message Request: Use right support url. Right now this just links to the profiles FAQ
        guard let url = URL(string: "https://support.signal.org/hc/en-us/articles/360007459591") else {
            return owsFailDebug("Invalid url.")
        }
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }
}
