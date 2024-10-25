//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension ProfileBadgesSnapshot {
    static func current() -> ProfileBadgesSnapshot {
        let profileSnapshot = SSKEnvironment.shared.profileManagerImplRef.localProfileSnapshot(shouldIncludeAvatar: false)
        return forSnapshot(profileSnapshot: profileSnapshot)
    }

    static func forSnapshot(profileSnapshot: OWSProfileSnapshot) -> ProfileBadgesSnapshot {
        ProfileBadgesSnapshot(
            existingBadges: (profileSnapshot.profileBadgeInfo ?? []).map {
                ProfileBadgesSnapshot.Badge(id: $0.badgeId, isVisible: $0.isVisible ?? false)
            }
        )
    }
}
