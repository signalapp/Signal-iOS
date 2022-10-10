// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Notification.Name {

    static let initialConfigurationMessageReceived = Notification.Name("initialConfigurationMessageReceived")
    static let missedCall = Notification.Name("missedCall")
}

public extension Notification.Key {
    static let senderId = Notification.Key("senderId")
}

@objc public extension NSNotification {

    @objc static let initialConfigurationMessageReceived = Notification.Name.initialConfigurationMessageReceived.rawValue as NSString
}
