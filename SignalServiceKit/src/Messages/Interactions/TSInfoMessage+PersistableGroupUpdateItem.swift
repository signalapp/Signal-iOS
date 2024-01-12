//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSInfoMessage {
    @objc(TSInfoMessageUpdateMessages)
    public class LegacyPersistableGroupUpdateItemsWrapper: NSObject, NSCopying, NSSecureCoding {
        public let updateItems: [LegacyPersistableGroupUpdateItem]

        public init(_ updateItems: [LegacyPersistableGroupUpdateItem]) {
            self.updateItems = updateItems
        }

        // MARK: NSCopying

        public func copy(with _: NSZone? = nil) -> Any {
            self
        }

        // MARK: NSSecureCoding

        public static var supportsSecureCoding: Bool { true }

        private static let messagesKey = "messagesKey"

        public func encode(with aCoder: NSCoder) {
            let jsonEncoder = JSONEncoder()
            do {
                let messagesData = try jsonEncoder.encode(updateItems)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode updateItems data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let updateItemsData = aDecoder.decodeObject(
                forKey: Self.messagesKey
            ) as? Data else {
                owsFailDebug("Failed to decode updateItems data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                updateItems = try jsonDecoder.decode(
                    [LegacyPersistableGroupUpdateItem].self,
                    from: updateItemsData
                )
            } catch let error {
                owsFailDebug("Failed to decode updateItems data: \(error)")
                return nil
            }

            super.init()
        }
    }

    @objc(TSInfoMessageUpdateMessagesV2)
    public class PersistableGroupUpdateItemsWrapper: NSObject, NSCopying, NSSecureCoding {
        public let updateItems: [PersistableGroupUpdateItem]

        public init(_ updateItems: [PersistableGroupUpdateItem]) {
            self.updateItems = updateItems
        }

        // MARK: NSCopying

        public func copy(with _: NSZone? = nil) -> Any {
            self
        }

        // MARK: NSSecureCoding

        public static var supportsSecureCoding: Bool { true }

        private static let messagesKey = "messagesKey"

        public func encode(with aCoder: NSCoder) {
            let jsonEncoder = JSONEncoder()
            do {
                let messagesData = try jsonEncoder.encode(updateItems)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode updateItems data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let updateItemsData = aDecoder.decodeObject(
                forKey: Self.messagesKey
            ) as? Data else {
                owsFailDebug("Failed to decode updateItems data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                updateItems = try jsonDecoder.decode(
                    [PersistableGroupUpdateItem].self,
                    from: updateItemsData
                )
            } catch let error {
                owsFailDebug("Failed to decode updateItems data: \(error)")
                return nil
            }

            super.init()
        }
    }
}

// MARK: -

extension TSInfoMessage {

    public enum LegacyPersistableGroupUpdateItem: Codable {
        enum CodingKeys: String, CodingKey {
            case sequenceOfInviteLinkRequestAndCancels
            case invitedPniPromotedToFullMemberAci
            case inviteRemoved
        }

        case sequenceOfInviteLinkRequestAndCancels(count: UInt, isTail: Bool)
        case invitedPniPromotedToFullMemberAci(pni: PniUuid, aci: AciUuid)
        case inviteRemoved(invitee: ServiceIdUppercaseString, wasLocalUser: Bool)

        func toNewItem(
            updater: GroupUpdateSource,
            oldGroupModel: TSGroupModel?,
            localIdentifiers: LocalIdentifiers?
        ) -> PersistableGroupUpdateItem? {
            switch self {
            case .sequenceOfInviteLinkRequestAndCancels(let count, let isTail):
                switch updater {
                case .unknown, .legacyE164, .rejectedInviteToPni:
                    owsFailDebug("How did we get one of these without an updater? that should be impossible")
                    return nil
                case .aci(let aci):
                    return .sequenceOfInviteLinkRequestAndCancels(
                        requester: aci.codableUuid,
                        count: count,
                        isTail: isTail
                    )
                }

            case .invitedPniPromotedToFullMemberAci(let pni, let aci):
                return .invitedPniPromotedToFullMemberAci(
                    newMember: aci,
                    inviter: oldGroupModel?.groupMembership.addedByAci(
                        forInvitedMember: SignalServiceAddress(pni.wrappedValue)
                    )?.codableUuid
                )
            case .inviteRemoved(let invitee, let wasLocalUser):
                let remover: ServiceId
                var wasRejectedInvite = false
                switch updater {
                case .unknown, .legacyE164:
                    owsFailDebug("Only acis or pnis can remove an invite")
                    return nil
                case .aci(let aci):
                    remover = aci
                case .rejectedInviteToPni(let pni):
                    remover = pni
                    wasRejectedInvite = true
                }

                let inviterAci = oldGroupModel?.groupMembership.addedByAci(
                    forInvitedMember: SignalServiceAddress(invitee.wrappedValue)
                )

                if wasLocalUser {
                    if wasRejectedInvite || (localIdentifiers?.contains(serviceId: remover) ?? false) {
                        // Local user invite that was rejected.
                        if let inviterAci {
                            return .localUserDeclinedInviteFromInviter(
                                inviterAci: inviterAci.codableUuid
                            )
                        } else {
                            return .localUserDeclinedInviteFromUnknownUser
                        }
                    } else {
                        // Local user invite that was removed by another user.
                        if let removerAci = remover as? Aci {
                            return .localUserInviteRevoked(revokerAci: removerAci.codableUuid)
                        } else {
                            return .localUserInviteRevokedByUnknownUser
                        }
                    }
                } else {
                    if wasRejectedInvite || invitee.wrappedValue == remover {
                        // Other user rejected an invite.
                        if let inviterAci {
                            if inviterAci == localIdentifiers?.aci {
                                return .otherUserDeclinedInviteFromLocalUser(invitee: invitee)
                            } else {
                                return .otherUserDeclinedInviteFromInviter(
                                    invitee: invitee,
                                    inviterAci: inviterAci.codableUuid
                                )
                            }
                        } else {
                            return .otherUserDeclinedInviteFromUnknownUser(invitee: invitee)
                        }
                    } else {
                        // Other user's invite was revoked.
                        if let removerAci = remover as? Aci {
                            if removerAci == localIdentifiers?.aci {
                                return .otherUserInviteRevokedByLocalUser(invitee: invitee)
                            } else {
                                return .unnamedUserInvitesWereRevokedByOtherUser(
                                    updaterAci: removerAci.codableUuid,
                                    count: 1
                                )
                            }
                        } else {
                            return .unnamedUserInvitesWereRevokedByUnknownUser(count: 1)
                        }
                    }
                }
            }
        }
    }

    public enum PersistableGroupUpdateItem: Codable {
        enum CodingKeys: String, CodingKey {
            case sequenceOfInviteLinkRequestAndCancels
            case invitedPniPromotedToFullMemberAci
            case localUserDeclinedInviteFromInviter
            case localUserDeclinedInviteFromUnknownUser
            case otherUserDeclinedInviteFromLocalUser
            case otherUserDeclinedInviteFromInviter
            case otherUserDeclinedInviteFromUnknownUser
            case unnamedUserDeclinedInviteFromInviter
            case unnamedUserDeclinedInviteFromUnknownUser
            case localUserInviteRevoked
            case localUserInviteRevokedByUnknownUser
            case otherUserInviteRevokedByLocalUser
            case unnamedUserInvitesWereRevokedByLocalUser
            case unnamedUserInvitesWereRevokedByOtherUser
            case unnamedUserInvitesWereRevokedByUnknownUser
        }

        case sequenceOfInviteLinkRequestAndCancels(requester: AciUuid, count: UInt, isTail: Bool)

        case invitedPniPromotedToFullMemberAci(newMember: AciUuid, inviter: AciUuid?)

        case localUserDeclinedInviteFromInviter(inviterAci: AciUuid)
        case localUserDeclinedInviteFromUnknownUser
        case otherUserDeclinedInviteFromLocalUser(invitee: ServiceIdUppercaseString)
        case otherUserDeclinedInviteFromInviter(invitee: ServiceIdUppercaseString, inviterAci: AciUuid)
        case otherUserDeclinedInviteFromUnknownUser(invitee: ServiceIdUppercaseString)
        case unnamedUserDeclinedInviteFromInviter(inviterAci: AciUuid)
        case unnamedUserDeclinedInviteFromUnknownUser

        case localUserInviteRevoked(revokerAci: AciUuid)
        case localUserInviteRevokedByUnknownUser
        // For a single invite we revoked we keep the invitee.
        // For many, or if someone else revoked, we just keep the number.
        case otherUserInviteRevokedByLocalUser(invitee: ServiceIdUppercaseString)
        case unnamedUserInvitesWereRevokedByLocalUser(count: UInt)
        case unnamedUserInvitesWereRevokedByOtherUser(updaterAci: AciUuid, count: UInt)
        case unnamedUserInvitesWereRevokedByUnknownUser(count: UInt)

    }
}
