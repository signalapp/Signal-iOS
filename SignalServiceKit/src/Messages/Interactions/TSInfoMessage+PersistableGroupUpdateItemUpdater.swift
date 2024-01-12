//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSInfoMessage.PersistableGroupUpdateItem {

    func updater(
        localIdentifiers: LocalIdentifiers,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> GroupUpdater {
        let groupUpdateSource: GroupUpdateSource
        switch self {
        case .sequenceOfInviteLinkRequestAndCancels(let requester, _, _):
            groupUpdateSource = .aci(requester.wrappedValue)
        case .invitedPniPromotedToFullMemberAci(let newMember, _):
            // Only the invited member themselves can issue this update.
            if localIdentifiers.aci == newMember.wrappedValue {
                return .localUser
            } else {
                groupUpdateSource = .aci(newMember.wrappedValue)
            }
        case .localUserDeclinedInviteFromInviter:
            return .localUser
        case .localUserDeclinedInviteFromUnknownUser:
            return .localUser
        case
                let .otherUserDeclinedInviteFromLocalUser(invitee),
                let .otherUserDeclinedInviteFromInviter(invitee, _),
                let .otherUserDeclinedInviteFromUnknownUser(invitee):
            switch invitee.wrappedValue.concreteType {
            case .aci(let aci):
                groupUpdateSource = .aci(aci)
            case .pni(let pni):
                groupUpdateSource = .rejectedInviteToPni(pni)
            }
        case .localUserInviteRevoked(revokerAci: let revokerAci):
            groupUpdateSource = .aci(revokerAci.wrappedValue)
        case .localUserInviteRevokedByUnknownUser:
            return .unknown
        case .otherUserInviteRevokedByLocalUser:
            return .localUser
        case .unnamedUserInvitesWereRevokedByLocalUser:
            return .localUser
        case let .unnamedUserInvitesWereRevokedByOtherUser(updaterAci, _):
            groupUpdateSource = .aci(updaterAci.wrappedValue)
        case .unnamedUserInvitesWereRevokedByUnknownUser:
            return .unknown
        case .unnamedUserDeclinedInviteFromInviter:
            return .unknown
        case .unnamedUserDeclinedInviteFromUnknownUser:
            return .unknown
        }
        return GroupUpdater.build(
            localIdentifiers: localIdentifiers,
            groupUpdateSource: groupUpdateSource,
            updaterKnownToBeLocalUser: false,
            contactsManager: contactsManager,
            tx: tx
        )
    }

    /// When rendering a notification for a group upate, if the update has a specific
    /// "sender", we render the notification UI as if sent from that sender.
    public var senderForNotification: SignalServiceAddress? {
        let serviceId: ServiceId? = {
            switch self {
            case .sequenceOfInviteLinkRequestAndCancels(let requester, _, _):
                return requester.wrappedValue
            case .invitedPniPromotedToFullMemberAci(let newMember, _):
                return newMember.wrappedValue
            case .localUserDeclinedInviteFromInviter:
                return nil
            case .localUserDeclinedInviteFromUnknownUser:
                return nil
            case .otherUserDeclinedInviteFromLocalUser(let invitee):
                return invitee.wrappedValue
            case .otherUserDeclinedInviteFromInviter(let invitee, _):
                return invitee.wrappedValue
            case .otherUserDeclinedInviteFromUnknownUser(let invitee):
                return invitee.wrappedValue
            case .localUserInviteRevoked(let revokerAci):
                return revokerAci.wrappedValue
            case .localUserInviteRevokedByUnknownUser:
                return nil
            case .otherUserInviteRevokedByLocalUser:
                return nil
            case .unnamedUserInvitesWereRevokedByLocalUser:
                return nil
            case .unnamedUserInvitesWereRevokedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .unnamedUserInvitesWereRevokedByUnknownUser:
                return nil
            case .unnamedUserDeclinedInviteFromInviter:
                return nil
            case .unnamedUserDeclinedInviteFromUnknownUser:
                return nil
            }
        }()

        return serviceId.map { SignalServiceAddress($0) }
    }
}
