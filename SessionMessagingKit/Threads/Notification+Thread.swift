
public extension Notification.Name {

    static let groupThreadUpdated = Notification.Name("groupThreadUpdated")
}

@objc public extension NSNotification {

    @objc static let groupThreadUpdated = Notification.Name.groupThreadUpdated.rawValue as NSString
}
