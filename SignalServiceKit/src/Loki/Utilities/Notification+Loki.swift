
public extension Notification.Name {
    public static let contactOnlineStatusChanged = Notification.Name("contactOnlineStatusChanged")
    public static let receivedNewMessages = Notification.Name("receivedNewMessages")
    
    // Friend request
    public static let threadFriendRequestStatusChanged = Notification.Name("threadFriendRequestStatusChanged")
    public static let messageFriendRequestStatusChanged = Notification.Name("messageFriendRequestStatusChanged")
}

// MARK: - Obj-C

@objc public extension NSNotification {
    @objc public static let contactOnlineStatusChanged = Notification.Name.contactOnlineStatusChanged.rawValue as NSString
    @objc public static let receivedNewMessages = Notification.Name.receivedNewMessages.rawValue as NSString
    
    // Friend request
    @objc public static let threadFriendRequestStatusChanged = Notification.Name.threadFriendRequestStatusChanged.rawValue as NSString
    @objc public static let messageFriendRequestStatusChanged = Notification.Name.messageFriendRequestStatusChanged.rawValue as NSString
}
