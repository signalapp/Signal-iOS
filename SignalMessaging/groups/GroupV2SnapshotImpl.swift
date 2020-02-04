//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

// GroupsV2 TODO: This class is likely to be reworked heavily as we
// start to apply it.
public struct GroupV2SnapshotImpl: GroupV2Snapshot {

    public struct Member {
        let userID: Data
        let uuid: UUID
        var address: SignalServiceAddress {
            return SignalServiceAddress(uuid: uuid)
        }
        let role: GroupsProtoMemberRole
        let profileKey: Data
        let joinedAtVersion: UInt32
    }

    public struct PendingMember {
        let userID: Data
        let uuid: UUID
        var address: SignalServiceAddress {
            return SignalServiceAddress(uuid: uuid)
        }
        let timestamp: UInt64
        let role: GroupsProtoMemberRole
        let addedByUuid: UUID
    }

    public let groupSecretParamsData: Data

    public let groupProto: GroupsProtoGroup

    public let revision: UInt32

    public let title: String

    private let members: [Member]
    private let pendingMembers: [PendingMember]

    public let accessControlForAttributes: GroupsProtoAccessControlAccessRequired
    public let accessControlForMembers: GroupsProtoAccessControlAccessRequired

    public let disappearingMessageToken: DisappearingMessageToken

    public let profileKeys: [UUID: Data]

    public var debugDescription: String {
        return groupProto.debugDescription
    }

    public init(groupSecretParamsData: Data,
                groupProto: GroupsProtoGroup,
                revision: UInt32,
                title: String,
                members: [Member],
                pendingMembers: [PendingMember],
                accessControlForAttributes: GroupsProtoAccessControlAccessRequired,
                accessControlForMembers: GroupsProtoAccessControlAccessRequired,
                disappearingMessageToken: DisappearingMessageToken,
                profileKeys: [UUID: Data]) {

        self.groupSecretParamsData = groupSecretParamsData
        self.groupProto = groupProto
        self.revision = revision
        self.title = title
        self.members = members
        self.pendingMembers = pendingMembers
        self.accessControlForAttributes = accessControlForAttributes
        self.accessControlForMembers = accessControlForMembers
        self.disappearingMessageToken = disappearingMessageToken
        self.profileKeys = profileKeys
    }

    public var groupMembership: GroupMembership {
        var builder = GroupMembership.Builder()
        for member in members {
            switch member.role {
            case .administrator:
                builder.addNonPendingMember(member.address, isAdministrator: true)
            default:
                builder.addNonPendingMember(member.address, isAdministrator: false)
            }
        }

        for member in pendingMembers {
            switch member.role {
            case .administrator:
                builder.addPendingMember(member.address, isAdministrator: true, addedByUuid: member.addedByUuid)
            default:
                builder.addPendingMember(member.address, isAdministrator: false, addedByUuid: member.addedByUuid)
            }
        }

        return builder.build()
    }

    public var groupAccess: GroupAccess {
        return GroupAccess(member: GroupAccess.groupV2Access(forProtoAccess: accessControlForMembers),
                           attributes: GroupAccess.groupV2Access(forProtoAccess: accessControlForAttributes))
    }
}
