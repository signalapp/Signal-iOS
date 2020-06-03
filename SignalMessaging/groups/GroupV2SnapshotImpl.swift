//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

public struct GroupV2SnapshotImpl: GroupV2Snapshot {

    public struct Member {
        let userID: Data
        let uuid: UUID
        var address: SignalServiceAddress {
            return SignalServiceAddress(uuid: uuid)
        }
        let role: GroupsProtoMemberRole
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

    public let avatarUrlPath: String?
    public let avatarData: Data?

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
                avatarUrlPath: String?,
                avatarData: Data?,
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
        self.avatarUrlPath = avatarUrlPath
        self.avatarData = avatarData
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
            guard let role = TSGroupMemberRole.role(for: member.role) else {
                owsFailDebug("Invalid value: \(member.role.rawValue)")
                continue
            }
            builder.addNonPendingMember(member.address, role: role)
        }

        for member in pendingMembers {
            guard let role = TSGroupMemberRole.role(for: member.role) else {
                owsFailDebug("Invalid value: \(member.role.rawValue)")
                continue
            }
            builder.addPendingMember(member.address, role: role, addedByUuid: member.addedByUuid)
        }

        return builder.build()
    }

    public var groupAccess: GroupAccess {
        return GroupAccess(members: GroupAccess.groupV2Access(forProtoAccess: accessControlForMembers),
                           attributes: GroupAccess.groupV2Access(forProtoAccess: accessControlForAttributes))
    }
}
