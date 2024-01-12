//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

extension TSInfoMessage.PersistableGroupUpdateItem {

    func cvComponentAction(
        groupThread: () -> TSGroupThread?,
        contactsManager: ContactsManagerProtocol,
        tx: SDSAnyReadTransaction
    ) -> CVComponentSystemMessage.Action? {
        switch self {
        case let .sequenceOfInviteLinkRequestAndCancels(requester, _, isTail):
            return .sequenceOfInviteLinkRequestAndCancelsAction(
                requester: requester.wrappedValue,
                isTail: isTail,
                groupThread: groupThread,
                contactsManager: contactsManager,
                tx: tx
            )
        case .invitedPniPromotedToFullMemberAci:
            return nil
        case .localUserDeclinedInviteFromInviter:
            return nil
        case .localUserDeclinedInviteFromUnknownUser:
            return nil
        case .otherUserDeclinedInviteFromLocalUser:
            return nil
        case .otherUserDeclinedInviteFromInviter:
            return nil
        case .otherUserDeclinedInviteFromUnknownUser:
            return nil
        case .localUserInviteRevoked:
            return nil
        case .localUserInviteRevokedByUnknownUser:
            return nil
        case .otherUserInviteRevokedByLocalUser:
            return nil
        case .unnamedUserInvitesWereRevokedByLocalUser:
            return nil
        case .unnamedUserInvitesWereRevokedByOtherUser:
            return nil
        case .unnamedUserInvitesWereRevokedByUnknownUser:
            return nil
        case .unnamedUserDeclinedInviteFromInviter:
            return nil
        case .unnamedUserDeclinedInviteFromUnknownUser:
            return nil
        }
    }
}

extension CVComponentSystemMessage.Action {

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
}
