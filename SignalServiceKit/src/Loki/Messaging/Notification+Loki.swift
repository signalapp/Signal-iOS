
public extension Notification.Name {
    public static let contactOnlineStatusChanged = Notification.Name("contactOnlineStatusChanged")
    public static let newMessagesReceived = Notification.Name("newMessagesReceived")
    public static let threadFriendRequestStatusChanged = Notification.Name("threadFriendRequestStatusChanged")
    public static let messageFriendRequestStatusChanged = Notification.Name("messageFriendRequestStatusChanged")
    public static let threadDeleted = Notification.Name("threadDeleted")
    public static let dataNukeRequested = Notification.Name("dataNukeRequested")
    // Message statuses
    public static let calculatingPoW = Notification.Name("calculatingPoW")
    public static let contactingNetwork = Notification.Name("contactingNetwork")
    public static let sendingMessage = Notification.Name("sendingMessage")
    public static let messageSent = Notification.Name("messageSent")
    public static let messageFailed = Notification.Name("messageFailed")
    // Onboarding
    public static let seedViewed = Notification.Name("seedViewed")
}

@objc public extension NSNotification {
    @objc public static let contactOnlineStatusChanged = Notification.Name.contactOnlineStatusChanged.rawValue as NSString
    @objc public static let newMessagesReceived = Notification.Name.newMessagesReceived.rawValue as NSString
    @objc public static let threadFriendRequestStatusChanged = Notification.Name.threadFriendRequestStatusChanged.rawValue as NSString
    @objc public static let messageFriendRequestStatusChanged = Notification.Name.messageFriendRequestStatusChanged.rawValue as NSString
    @objc public static let threadDeleted = Notification.Name.threadDeleted.rawValue as NSString
    @objc public static let dataNukeRequested = Notification.Name.dataNukeRequested.rawValue as NSString
    // Message statuses
    @objc public static let calculatingPoW = Notification.Name.calculatingPoW.rawValue as NSString
    @objc public static let contactingNetwork = Notification.Name.contactingNetwork.rawValue as NSString
    @objc public static let sendingMessage = Notification.Name.sendingMessage.rawValue as NSString
    @objc public static let messageSent = Notification.Name.messageSent.rawValue as NSString
    @objc public static let messageFailed = Notification.Name.messageFailed.rawValue as NSString
    // Onboarding
    @objc public static let seedViewed = Notification.Name.seedViewed.rawValue as NSString
}
