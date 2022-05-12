// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import SessionUtilitiesKit

public extension Notification.Name {

    static let profileUpdated = Notification.Name("profileUpdated")
    static let localProfileDidChange = Notification.Name("localProfileDidChange")
    static let otherUsersProfileDidChange = Notification.Name("otherUsersProfileDidChange")
}

@objc public extension NSNotification {

    @objc static let profileUpdated = Notification.Name.profileUpdated.rawValue as NSString
    @objc static let localProfileDidChange = Notification.Name.localProfileDidChange.rawValue as NSString
    @objc static let otherUsersProfileDidChange = Notification.Name.otherUsersProfileDidChange.rawValue as NSString
}

extension Notification.Key {
    static let profileRecipientId = Notification.Key("profileRecipientId")
}

@objc public extension NSNotification {
    static let profileRecipientIdKey = Notification.Key.profileRecipientId.rawValue as NSString
}
