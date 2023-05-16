//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol GroupViewHelperDelegate: AnyObject {
    func groupViewHelperDidUpdateGroup()

    var currentGroupModel: TSGroupModel? { get }

    var fromViewController: UIViewController? { get }
}

// MARK: -

class GroupViewHelper: Dependencies {

    weak var delegate: GroupViewHelperDelegate?

    let threadViewModel: ThreadViewModel

    var thread: TSThread {
        return threadViewModel.threadRecord
    }

    var fromViewController: UIViewController? {
        return delegate?.fromViewController
    }

    init(threadViewModel: ThreadViewModel) {
        self.threadViewModel = threadViewModel
    }

    // MARK: - Accessors

    // Don't use this method directly;
    // Use canEditConversationAttributes or canEditConversationMembership instead.
    private func canLocalUserEditConversation(v2AccessTypeBlock: (GroupAccess) -> GroupV2Access) -> Bool {
        if threadViewModel.hasPendingMessageRequest {
            return false
        }
        guard isLocalUserFullMember else {
            return false
        }
        guard let groupThread = thread as? TSGroupThread else {
            // Both users can edit contact threads.
            return true
        }
        guard !isBlockedByMigration else {
            return false
        }
        guard !threadViewModel.isBlocked else {
            return false
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            // All users can edit v1 groups.
            return true
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        // Use the block to pick the access type: attributes or members?
        let access = v2AccessTypeBlock(groupModelV2.access)
        switch access {
        case .unknown:
            owsFailDebug("Unknown access.")
            return false
        case .unsatisfiable:
            owsFailDebug("Invalid access.")
            return false
        case .any:
            return true
        case .member:
            return groupModelV2.groupMembership.isFullMember(localAddress)
        case .administrator:
            return (groupModelV2.groupMembership.isFullMemberAndAdministrator(localAddress))
        }
    }

    var isBlockedByMigration: Bool {
        thread.isBlockedByMigration
    }

    // Can local user edit conversation attributes:
    //
    // * DM state
    // * Group title (if group)
    // * Group avatar (if group)
    var canEditConversationAttributes: Bool {
        return canLocalUserEditConversation { groupAccess in
            return groupAccess.attributes
        }
    }

    // Can local user edit group membership.
    var canEditConversationMembership: Bool {
        return canLocalUserEditConversation { groupAccess in
            return groupAccess.members
        }
    }

    // Can local user edit group access and message send permission.
    var canEditPermissions: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return (!threadViewModel.hasPendingMessageRequest &&
            groupThread.isGroupV2Thread &&
            groupThread.isLocalUserFullMemberAndAdministrator)
    }

    var canRevokePendingInvites: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return (!threadViewModel.hasPendingMessageRequest &&
            groupThread.isGroupV2Thread &&
            groupThread.isLocalUserFullMemberAndAdministrator)
    }

    var canResendInvites: Bool {
        return (!threadViewModel.hasPendingMessageRequest && isLocalUserFullMember)
    }

    var canApproveMemberRequests: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return (!threadViewModel.hasPendingMessageRequest &&
            groupThread.isGroupV2Thread &&
            groupThread.isLocalUserFullMemberAndAdministrator)
    }

    var isLocalUserFullMember: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return true
        }
        return groupThread.isLocalUserFullMember
    }

    var isLocalUserFullOrInvitedMember: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return true
        }
        return groupThread.isLocalUserFullOrInvitedMember
    }

    func isFullOrInvitedMember(_ address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        let groupMembership = groupThread.groupModel.groupMembership
        return groupMembership.isFullMember(address) || groupMembership.isInvitedMember(address)
    }
}
