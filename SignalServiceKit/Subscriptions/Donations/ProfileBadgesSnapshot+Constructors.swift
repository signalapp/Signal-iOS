//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension ProfileBadgesSnapshot {
    static func forLocalProfile(profileManager: any ProfileManager, tx: SDSAnyReadTransaction) -> ProfileBadgesSnapshot {
        let badgeInfos = profileManager.localUserProfile(tx: tx)?.badges ?? []
        return ProfileBadgesSnapshot(existingBadges: badgeInfos.map {
            return ProfileBadgesSnapshot.Badge(id: $0.badgeId, isVisible: $0.isVisible ?? false)
        })
    }
}
