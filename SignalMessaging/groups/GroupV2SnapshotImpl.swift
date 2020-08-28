//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

public struct GroupV2SnapshotImpl: GroupV2Snapshot {

    public let groupSecretParamsData: Data

    public let groupProto: GroupsProtoGroup

    public let revision: UInt32

    public let title: String

    public let avatarUrlPath: String?
    public let avatarData: Data?

    public let groupMembership: GroupMembership

    public let groupAccess: GroupAccess

    public let inviteLinkPassword: Data?

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
                groupMembership: GroupMembership,
                groupAccess: GroupAccess,
                inviteLinkPassword: Data?,
                disappearingMessageToken: DisappearingMessageToken,
                profileKeys: [UUID: Data]) {

        self.groupSecretParamsData = groupSecretParamsData
        self.groupProto = groupProto
        self.revision = revision
        self.title = title
        self.avatarUrlPath = avatarUrlPath
        self.avatarData = avatarData
        self.groupMembership = groupMembership
        self.groupAccess = groupAccess
        self.inviteLinkPassword = inviteLinkPassword
        self.disappearingMessageToken = disappearingMessageToken
        self.profileKeys = profileKeys
    }
}
