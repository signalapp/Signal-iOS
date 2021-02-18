
public extension Notification.Name {

    static let configurationMessageReceived = Notification.Name("configurationMessageReceived")
}

@objc public extension NSNotification {

    @objc static let configurationMessageReceived = Notification.Name.configurationMessageReceived.rawValue as NSString
}
