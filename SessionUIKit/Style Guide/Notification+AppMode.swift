
public extension Notification.Name {

    static let appModeChanged = Notification.Name("appModeChanged")
}

@objc public extension NSNotification {

    @objc public static let appModeChanged = Notification.Name.appModeChanged.rawValue as NSString
}
