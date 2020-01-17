//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

// GroupsV2 TODO: This class is likely to be reworked heavily as we
// start to apply it.
public struct GroupV2StateImpl: GroupV2State {

    struct Member {
        let userID: Data
        let uuid: UUID
        var address: SignalServiceAddress {
            return SignalServiceAddress(uuid: uuid)
        }
        let role: GroupsProtoMemberRole
        let profileKey: Data
        let joinedAtVersion: UInt32
    }

    struct PendingMember {
        let userID: Data
        let uuid: UUID
        let timestamp: UInt64
    }

    public let groupSecretParamsData: Data

    public let groupProto: GroupsProtoGroup

    public let version: UInt32

    public let title: String

    let members: [Member]
    let pendingMembers: [PendingMember]

    public let accessControlForAttributes: GroupsProtoAccessControlAccessRequired
    public let accessControlForMembers: GroupsProtoAccessControlAccessRequired

    public var debugDescription: String {
        return groupProto.debugDescription
    }

    public var activeMembers: [SignalServiceAddress] {
        return members.map { $0.address }
    }

    public var administrators: [SignalServiceAddress] {
        return members.compactMap { member in
            guard member.role == .administrator else {
                return nil
            }
            return member.address
        }
    }
}
