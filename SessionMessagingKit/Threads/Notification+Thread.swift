
public extension Notification.Name {

    static let groupThreadUpdated = Notification.Name("groupThreadUpdated")
    static let muteSettingUpdated = Notification.Name("muteSettingUpdated")
}

@objc public extension NSNotification {

    @objc static let groupThreadUpdated = Notification.Name.groupThreadUpdated.rawValue as NSString
    @objc static let muteSettingUpdated = Notification.Name.muteSettingUpdated.rawValue as NSString
}
