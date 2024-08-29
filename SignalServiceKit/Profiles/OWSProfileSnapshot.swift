//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: Remove @objc and convert to struct
@objc
public class OWSProfileSnapshot: NSObject {
    public let givenName: String?
    public let familyName: String?
    public let fullName: String?
    public let bio: String?
    public let bioEmoji: String?

    public let avatarData: Data?
    public let profileBadgeInfo: [OWSUserProfileBadgeInfo]?

    @objc(initWithGivenName:familyName:fullName:bio:bioEmoji:avatarData:profileBadgeInfo:)
    init(givenName: String?, familyName: String?, fullName: String?, bio: String?, bioEmoji: String?, avatarData: Data?, profileBadgeInfo: [OWSUserProfileBadgeInfo]?) {
        self.givenName = givenName
        self.familyName = familyName
        self.fullName = fullName
        self.bio = bio
        self.bioEmoji = bioEmoji
        self.avatarData = avatarData
        self.profileBadgeInfo = profileBadgeInfo
    }
}
