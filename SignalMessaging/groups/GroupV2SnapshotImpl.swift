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
                disappearingMessageToken: DisappearingMessageToken) {

        self.groupSecretParamsData = groupSecretParamsData
        self.groupProto = groupProto
        self.revision = revision
        self.title = title
        self.members = members
        self.pendingMembers = pendingMembers
        self.accessControlForAttributes = accessControlForAttributes
        self.accessControlForMembers = accessControlForMembers
        self.disappearingMessageToken = disappearingMessageToken
    }

    public var groupMembership: GroupMembership {
        var nonAdminMembers = Set<SignalServiceAddress>()
        var administrators = Set<SignalServiceAddress>()
        for member in members {
            switch member.role {
            case .administrator:
                administrators.insert(member.address)
            default:
                nonAdminMembers.insert(member.address)
            }
        }

        var pendingNonAdminMembers = Set<SignalServiceAddress>()
        var pendingAdministrators = Set<SignalServiceAddress>()
        for member in pendingMembers {
            switch member.role {
            case .administrator:
                pendingAdministrators.insert(member.address)
            default:
                pendingNonAdminMembers.insert(member.address)
            }
        }

        return GroupMembership(nonAdminMembers: nonAdminMembers,
                               administrators: administrators,
                               pendingNonAdminMembers: pendingNonAdminMembers,
                               pendingAdministrators: pendingAdministrators)
    }

    public var groupAccess: GroupAccess {
        return GroupAccess(member: GroupAccess.groupV2Access(forProtoAccess: accessControlForMembers),
                           attributes: GroupAccess.groupV2Access(forProtoAccess: accessControlForAttributes))
    }
}
