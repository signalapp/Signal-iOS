//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalMessaging
import SignalServiceKit

extension TSInfoMessage.PersistableGroupUpdateItem {

    static func cvComponentAction(
        items: [Self],
        groupThread: () -> TSGroupThread?,
        contactsManager: ContactsManagerProtocol,
        tx: SDSAnyReadTransaction
    ) -> CVComponentSystemMessage.Action? {
        guard !items.isEmpty else {
            return nil
        }

        // Cache the group thread so we only fetch it once.
        var hasFetchedGroupThread = false
        var cachedGroupThread: TSGroupThread?
        let cachingGroupThread: () -> TSGroupThread? = {
            if hasFetchedGroupThread {
                return cachedGroupThread
            } else {
                return groupThread()
            }
        }

        var index = 0
        while index < items.count {
            let item = items[index]
            defer {
                index += 1
            }

            /// Normally we use the action from the first non-nil item
            /// on the info message.
            /// It is legal, in a backup, to have a single TSInfoMessage
            /// with both a collapsed .sequenceOfInviteLinkRequestAndCancels
            /// and a single request to join right after. (Which implies the
            /// sequence ends in a cancel, and a new request came after).
            /// In this case we want to show the action from the request to join
            /// (an "accept request" item) that follows, so do a little lookahead
            /// to catch this exception case.
            if
                case let .sequenceOfInviteLinkRequestAndCancels(_, _, isTail) = item,
                let nextItem = items[safe: index + 1],
                nextItem.representsCollapsibleSingleRequestToJoin() != nil,
                let nextItemAction = item.cvComponentAction(
                    groupThread: cachingGroupThread,
                    contactsManager: contactsManager,
                    tx: tx
                )
            {
                owsAssertDebug(
                    isTail.negated,
                    "Collapsed item with a following request shouldn't be a tail!"
                )
                return nextItemAction
            }

            if let action = item.cvComponentAction(
                groupThread: cachingGroupThread,
                contactsManager: contactsManager,
                tx: tx
            ) {
                return action
            }
        }
        return nil
    }

    private func cvComponentAction(
        groupThread: () -> TSGroupThread?,
        contactsManager: ContactsManagerProtocol,
        tx: SDSAnyReadTransaction
    ) -> CVComponentSystemMessage.Action? {
        typealias Action = CVComponentSystemMessage.Action

        switch self {
        case let .sequenceOfInviteLinkRequestAndCancels(requester, count, isTail):
            if count == 0 {
                // This is just a request to join.
                return Action.forNewlyRequestingMembers(count: 1)
            }
            return Action.sequenceOfInviteLinkRequestAndCancelsAction(
                requester: requester.wrappedValue,
                isTail: isTail,
                groupThread: groupThread,
                contactsManager: contactsManager,
                tx: tx
            )
        case .inviteFriendsToNewlyCreatedGroup:
            // We should use the latest group model, not the one from the time
            // the info message was made.
            guard let thread = groupThread() else {
                return nil
            }
            return Action(
                title: OWSLocalizedString(
                    "GROUPS_INVITE_FRIENDS_BUTTON",
                    comment: "Label for 'invite friends to group' button."
                ),
                accessibilityIdentifier: "group_invite_friends",
                action: .didTapGroupInviteLinkPromotion(groupModel: thread.groupModel)
            )
        case .wasMigrated:
            return Action(
                title: CommonStrings.learnMore,
                accessibilityIdentifier: "group_migration_learn_more",
                action: .didTapGroupMigrationLearnMore
            )
        case
                .descriptionChangedByLocalUser(let newGroupDescription),
                .descriptionChangedByOtherUser(_, let newGroupDescription),
                .descriptionChangedByUnknownUser(let newGroupDescription):
            return Action(
                title: CommonStrings.viewButton,
                accessibilityIdentifier: "group_description_view",
                action: .didTapViewGroupDescription(newGroupDescription: newGroupDescription)
            )
        case
            let .unnamedUserInvitesWereRevokedByLocalUser(count),
            let .unnamedUsersWereInvitedByOtherUser(_, count),
            let .unnamedUsersWereInvitedByUnknownUser(count):
            return Action.forNewlyRequestingMembers(count: count)
        case .localUserRequestedToJoin, .otherUserRequestedToJoin:
            return Action.forNewlyRequestingMembers(count: 1)

        default:
            return nil
        }
    }
}

fileprivate extension CVComponentSystemMessage.Action {

    static func sequenceOfInviteLinkRequestAndCancelsAction(
        requester: Aci,
        isTail: Bool,
        groupThread: () -> TSGroupThread?,
        contactsManager: ContactsManagerProtocol,
        tx: SDSAnyReadTransaction
    ) -> Self? {
        guard isTail else { return nil }

        guard
            let mostRecentGroupModel = groupThread()?.groupModel as? TSGroupModelV2
        else {
            owsFailDebug("Missing group thread for join request sequence")
            return nil
        }

        // Only show the option to ban if we are an admin, and they are
        // not already banned. We want to use the most up-to-date group
        // model here instead of the one on the info message, since
        // group state may have changed since that message.
        guard
            mostRecentGroupModel.groupMembership.isLocalUserFullMemberAndAdministrator,
            !mostRecentGroupModel.groupMembership.isBannedMember(requester)
        else {
            return nil
        }

        return CVComponentSystemMessage.Action(
            title: OWSLocalizedString(
                "GROUPS_BLOCK_REQUEST_BUTTON",
                comment: "Label for button that lets the user block a request to join the group."
            ),
            accessibilityIdentifier: "block_join_request_button",
            action: .didTapBlockRequest(
                groupModel: mostRecentGroupModel,
                requesterName: contactsManager.shortDisplayName(
                    for: SignalServiceAddress(requester),
                    transaction: tx
                ),
                requesterAci: requester
            )
        )
    }

    static func forNewlyRequestingMembers(count: UInt) -> Self {
        let title: String = {
            if count > 1 {
                return OWSLocalizedString(
                    "GROUPS_VIEW_REQUESTS_BUTTON",
                    comment: "Label for button that lets the user view the requests to join the group."
                )
            } else {
                return OWSLocalizedString(
                    "GROUPS_VIEW_REQUEST_BUTTON",
                    comment: "Label for button that lets the user view the request to join the group."
                )
            }
        }()

        return Self(
            title: title,
            accessibilityIdentifier: "show_group_requests_button",
            action: .didTapShowConversationSettingsAndShowMemberRequests
        )
    }
}
