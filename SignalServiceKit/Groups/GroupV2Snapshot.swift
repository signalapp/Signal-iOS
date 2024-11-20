//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct GroupV2SnapshotResponse {
    let groupSnapshot: GroupV2Snapshot
    let groupSendEndorsements: Data?
}

public struct GroupV2Snapshot {
    let groupSecretParams: GroupSecretParams
    let revision: UInt32
    let title: String
    let descriptionText: String?
    let avatarUrlPath: String?
    let avatarData: Data?
    let groupMembership: GroupMembership
    let groupAccess: GroupAccess
    let inviteLinkPassword: Data?
    let disappearingMessageToken: DisappearingMessageToken
    let isAnnouncementsOnly: Bool
    let profileKeys: [Aci: Data]
}
