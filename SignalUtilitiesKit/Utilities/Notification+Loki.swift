
public extension Notification.Name {

    // State changes
    static let blockedContactsUpdated = Notification.Name("blockedContactsUpdated")
    static let contactOnlineStatusChanged = Notification.Name("contactOnlineStatusChanged")
    static let threadDeleted = Notification.Name("threadDeleted")
    static let threadSessionRestoreDevicesChanged = Notification.Name("threadSessionRestoreDevicesChanged")
    // Onboarding
    static let seedViewed = Notification.Name("seedViewed")
    // Interaction
    static let dataNukeRequested = Notification.Name("dataNukeRequested")
}

@objc public extension NSNotification {

    // State changes
    @objc static let blockedContactsUpdated = Notification.Name.blockedContactsUpdated.rawValue as NSString
    @objc static let contactOnlineStatusChanged = Notification.Name.contactOnlineStatusChanged.rawValue as NSString
    @objc static let threadDeleted = Notification.Name.threadDeleted.rawValue as NSString
    @objc static let threadSessionRestoreDevicesChanged = Notification.Name.threadSessionRestoreDevicesChanged.rawValue as NSString
    // Onboarding
    @objc static let seedViewed = Notification.Name.seedViewed.rawValue as NSString
    // Interaction
    @objc static let dataNukeRequested = Notification.Name.dataNukeRequested.rawValue as NSString
}
