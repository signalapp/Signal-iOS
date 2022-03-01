
public extension Notification.Name {

    static let groupThreadUpdated = Notification.Name("groupThreadUpdated")
    static let muteSettingUpdated = Notification.Name("muteSettingUpdated")
    static let messageSentStatusDidChange = Notification.Name("messageSentStatusDidChange")
    static let contactThreadReplaced = Notification.Name("contactThreadReplaced")
}

@objc public extension NSNotification {

    @objc static let groupThreadUpdated = Notification.Name.groupThreadUpdated.rawValue as NSString
    @objc static let muteSettingUpdated = Notification.Name.muteSettingUpdated.rawValue as NSString
    @objc static let messageSentStatusDidChange = Notification.Name.messageSentStatusDidChange.rawValue as NSString
}

public enum NotificationUserInfoKey: String {
    case threadId
    case removedThreadIds
}
