
public extension Notification.Name {

    static let contactUpdated = Notification.Name("contactUpdated")
    static let contactBlockedStateChanged = Notification.Name("contactBlockedStateChanged")
}

@objc public extension NSNotification {

    @objc static let contactUpdated = Notification.Name.contactUpdated.rawValue as NSString
    @objc static let contactBlockedStateChanged = Notification.Name.contactBlockedStateChanged.rawValue as NSString
}
