
public extension Notification.Name {

    static let encryptingMessage = Notification.Name("encryptingMessage")
    static let calculatingMessagePoW = Notification.Name("calculatingPoW")
    static let messageSending = Notification.Name("messageSending")
    static let messageSent = Notification.Name("messageSent")
    static let messageSendingFailed = Notification.Name("messageSendingFailed")
}

@objc public extension NSNotification {

    @objc static let encryptingMessage = Notification.Name.encryptingMessage.rawValue as NSString
    @objc static let calculatingMessagePoW = Notification.Name.calculatingMessagePoW.rawValue as NSString
    @objc static let messageSending = Notification.Name.messageSending.rawValue as NSString
    @objc static let messageSent = Notification.Name.messageSent.rawValue as NSString
    @objc static let messageSendingFailed = Notification.Name.messageSendingFailed.rawValue as NSString
}
