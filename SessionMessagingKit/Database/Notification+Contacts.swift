
public extension Notification.Name {

    static let contactUpdated = Notification.Name("contactUpdated")
}

@objc public extension NSNotification {

    @objc static let contactUpdated = Notification.Name.contactUpdated.rawValue as NSString
}
