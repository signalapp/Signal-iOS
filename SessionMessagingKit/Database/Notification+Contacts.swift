// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import SessionUtilitiesKit
// FIXME: Remove these extensions once the OWSConversationSettingsViewModel is refactored to swift and uses proper database observation
public extension Notification.Name {

    static let otherUsersProfileDidChange = Notification.Name("otherUsersProfileDidChange")
}

@objc public extension NSNotification {

    @objc static let otherUsersProfileDidChange = Notification.Name.otherUsersProfileDidChange.rawValue as NSString
}

extension Notification.Key {
    static let profileRecipientId = Notification.Key("profileRecipientId")
}

@objc public extension NSNotification {
    static let profileRecipientIdKey = Notification.Key.profileRecipientId.rawValue as NSString
}
