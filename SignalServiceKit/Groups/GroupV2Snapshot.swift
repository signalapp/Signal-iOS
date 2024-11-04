//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct GroupV2Snapshot {

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
}
