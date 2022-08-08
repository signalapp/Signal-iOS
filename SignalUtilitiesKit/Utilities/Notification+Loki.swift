import Foundation

public extension Notification.Name {

    // State changes
    static let contactOnlineStatusChanged = Notification.Name("contactOnlineStatusChanged")
    static let threadDeleted = Notification.Name("threadDeleted")
    static let threadSessionRestoreDevicesChanged = Notification.Name("threadSessionRestoreDevicesChanged")
}

@objc public extension NSNotification {

    // State changes
    @objc static let contactOnlineStatusChanged = Notification.Name.contactOnlineStatusChanged.rawValue as NSString
    @objc static let threadDeleted = Notification.Name.threadDeleted.rawValue as NSString
    @objc static let threadSessionRestoreDevicesChanged = Notification.Name.threadSessionRestoreDevicesChanged.rawValue as NSString
}
