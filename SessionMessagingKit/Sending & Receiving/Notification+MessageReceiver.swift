
public extension Notification.Name {

    static let initialConfigurationMessageReceived = Notification.Name("initialConfigurationMessageReceived")
    static let incomingMessageMarkedAsRead = Notification.Name("incomingMessageMarkedAsRead")
}

@objc public extension NSNotification {

    @objc static let initialConfigurationMessageReceived = Notification.Name.initialConfigurationMessageReceived.rawValue as NSString
    @objc static let incomingMessageMarkedAsRead = Notification.Name.incomingMessageMarkedAsRead.rawValue as NSString
}
