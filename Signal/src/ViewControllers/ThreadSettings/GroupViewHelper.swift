//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
protocol GroupViewHelperDelegate: class {
    func groupViewHelperDidUpdateGroup()

    var currentGroupModel: TSGroupModel? { get }

    var fromViewController: UIViewController? { get }
}

// MARK: -

@objc
class GroupViewHelper: NSObject {

    // MARK: - Dependencies

    var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    // MARK: -

    @objc
    weak var delegate: GroupViewHelperDelegate?

    let threadViewModel: ThreadViewModel

    var thread: TSThread {
        return threadViewModel.threadRecord
    }

    var fromViewController: UIViewController? {
        return delegate?.fromViewController
    }

    @objc
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
        guard isLocalUserInConversation else {
            return false
        }
        guard let groupThread = thread as? TSGroupThread else {
            // Both users can edit contact threads.
            return true
        }
        guard !blockingManager.isThreadBlocked(groupThread) else {
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
        case .any:
            return true
        case .member:
            return groupModelV2.groupMembership.isNonPendingMember(localAddress)
        case .administrator:
            return (groupModelV2.groupMembership.isNonPendingMember(localAddress) &&        groupModelV2.groupMembership.isAdministrator(localAddress))
        }
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

    // Can local user edit group access.
    var canEditConversationAccess: Bool {
        if threadViewModel.hasPendingMessageRequest {
            return false
        }
        guard isLocalUserInConversation else {
            return false
        }
        guard let groupThread = thread as? TSGroupThread else {
            // Contact threads don't use access.
            return false
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            // v1 groups don't use access.
            return false
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        return groupModelV2.groupMembership.isAdministrator(localAddress)
    }

    var canRevokePendingInvites: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        let groupMembership = groupThread.groupModel.groupMembership
        return (!threadViewModel.hasPendingMessageRequest &&
            groupMembership.isPendingOrNonPendingMember(localAddress) &&
            groupMembership.isAdministrator(localAddress))
    }

    var canResendInvites: Bool {
        return (!threadViewModel.hasPendingMessageRequest &&
            isLocalUserInConversation)
    }

    var isLocalUserInConversation: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return true
        }

        return groupThread.isLocalUserInGroup
    }
}
