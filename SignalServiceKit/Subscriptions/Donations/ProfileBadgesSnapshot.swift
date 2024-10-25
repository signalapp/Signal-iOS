//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A snapshot of the badges currently available on this user's profile.
public struct ProfileBadgesSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case existingBadges
    }

    public struct Badge: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case isVisible
        }

        public let id: String
        public let isVisible: Bool

        public init(id: String, isVisible: Bool) {
            self.id = id
            self.isVisible = isVisible
        }
    }

    public let existingBadges: [Badge]

    public init(existingBadges: [Badge]) {
        self.existingBadges = existingBadges
    }
}
