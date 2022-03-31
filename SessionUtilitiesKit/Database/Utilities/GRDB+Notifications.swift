// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Notification.Name {
    static let resetStorage = Notification.Name("resetStorage")
}

@objc public extension NSNotification {
    @objc static let resetStorage = Notification.Name.resetStorage.rawValue as NSString
}
