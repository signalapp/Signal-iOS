
public extension Notification.Name {

    static let initialConfigurationMessageReceived = Notification.Name("initialConfigurationMessageReceived")
}

@objc public extension NSNotification {

    @objc static let initialConfigurationMessageReceived = Notification.Name.initialConfigurationMessageReceived.rawValue as NSString
}
