
public extension Notification.Name {
    public static let threadFriendRequestStatusChanged = Notification.Name("threadFriendRequestStatusChanged")
}

@objc public extension NSNotification {
    @objc public static let threadFriendRequestStatusChanged = Notification.Name.threadFriendRequestStatusChanged.rawValue as NSString // Obj-C
}
