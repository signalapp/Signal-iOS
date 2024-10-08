//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct GroupV2SnapshotImpl: GroupV2Snapshot {

    public let groupSecretParams: GroupSecretParams

    public let groupProto: GroupsProtoGroup

    public let revision: UInt32

    public let title: String
    public let descriptionText: String?

    public let avatarUrlPath: String?
    public let avatarData: Data?

    public let groupMembership: GroupMembership

    public let groupAccess: GroupAccess

    public let inviteLinkPassword: Data?

    public let disappearingMessageToken: DisappearingMessageToken

    public let isAnnouncementsOnly: Bool

    public let profileKeys: [Aci: Data]

    public var debugDescription: String {
        return groupProto.debugDescription
    }

    public init(
        groupSecretParams: GroupSecretParams,
        groupProto: GroupsProtoGroup,
        revision: UInt32,
        title: String,
        descriptionText: String?,
        avatarUrlPath: String?,
        avatarData: Data?,
        groupMembership: GroupMembership,
        groupAccess: GroupAccess,
        inviteLinkPassword: Data?,
        disappearingMessageToken: DisappearingMessageToken,
        isAnnouncementsOnly: Bool,
        profileKeys: [Aci: Data]
    ) {
        self.groupSecretParams = groupSecretParams
        self.groupProto = groupProto
        self.revision = revision
        self.title = title
        self.descriptionText = descriptionText
        self.avatarUrlPath = avatarUrlPath
        self.avatarData = avatarData
        self.groupMembership = groupMembership
        self.groupAccess = groupAccess
        self.inviteLinkPassword = inviteLinkPassword
        self.disappearingMessageToken = disappearingMessageToken
        self.isAnnouncementsOnly = isAnnouncementsOnly
        self.profileKeys = profileKeys
    }
}
