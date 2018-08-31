//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

/**
 * TODO This is currently unused code. I started implenting new notifications as UserNotifications rather than the deprecated
 * LocalNotifications before I realized we can't mix and match. Registering notifications for one clobbers the other.
 * So, for now iOS10 continues to use LocalNotifications until we can port all the NotificationsManager stuff here.
 */
import Foundation
import UserNotifications

@available(iOS 10.0, *)
struct AppNotifications {
    enum Category {
        case missedCall,
             missedCallFromNoLongerVerifiedIdentity

        // Don't forget to update this! We use it to register categories.
        static let allValues = [ missedCall, missedCallFromNoLongerVerifiedIdentity ]
    }

    enum Action {
        case callBack,
             showThread
    }

    static var allCategories: Set<UNNotificationCategory> {
        let categories = Category.allValues.map { category($0) }
        return Set(categories)
    }

    static func category(_ type: Category) -> UNNotificationCategory {
        switch type {
        case .missedCall:
            return UNNotificationCategory(identifier: "org.whispersystems.signal.AppNotifications.Category.missedCall",
                                          actions: [ action(.callBack) ],
                                          intentIdentifiers: [],
                                          options: [])

        case .missedCallFromNoLongerVerifiedIdentity:
            return UNNotificationCategory(identifier: "org.whispersystems.signal.AppNotifications.Category.missedCallFromNoLongerVerifiedIdentity",
                                          actions: [ action(.showThread) ],
                                          intentIdentifiers: [],
                                          options: [])
        }
    }

    static func action(_ type: Action) -> UNNotificationAction {
        switch type {
        case .callBack:
            return UNNotificationAction(identifier: "org.whispersystems.signal.AppNotifications.Action.callBack",
                                        title: CallStrings.callBackButtonTitle,
                                        options: .authenticationRequired)
        case .showThread:
            return UNNotificationAction(identifier: "org.whispersystems.signal.AppNotifications.Action.showThread",
                                        title: CallStrings.showThreadButtonTitle,
                                        options: .authenticationRequired)
        }
    }
}

@available(iOS 10.0, *)
class UserNotificationsAdaptee: NSObject, OWSCallNotificationsAdaptee, UNUserNotificationCenterDelegate {

    private let center: UNUserNotificationCenter

    var previewType: NotificationType {
        return Environment.shared.preferences.notificationPreviewType()
    }

    override init() {
        self.center = UNUserNotificationCenter.current()

        super.init()

        SwiftSingletons.register(self)

        center.delegate = self

        // FIXME TODO only do this after user has registered.
        // maybe the PushManager needs a reference to the NotificationsAdapter.
        requestAuthorization()

        center.setNotificationCategories(AppNotifications.allCategories)
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
            if granted {
                Logger.debug("succeeded.")
            } else if error != nil {
                Logger.error("failed with error: \(error!)")
            } else {
                Logger.error("failed without error.")
            }
        }
    }

    // MARK: - OWSCallNotificationsAdaptee

    public func presentIncomingCall(_ call: SignalCall, callerName: String) {
        Logger.debug("is no-op, because it's handled with callkit.")
        // TODO since CallKit doesn't currently work on the simulator,
        // we could implement UNNotifications for simulator testing, or if people have opted out of callkit.
    }

    public func presentMissedCall(_ call: SignalCall, callerName: String) {
        Logger.debug("")

        let content = UNMutableNotificationContent()
        // TODO group by thread identifier
        // content.threadIdentifier = threadId

        let notificationBody = { () -> String in
            switch previewType {
            case .noNameNoPreview:
                return CallStrings.missedCallNotificationBodyWithoutCallerName
            case .nameNoPreview, .namePreview:
                return (Environment.shared.preferences.isCallKitPrivacyEnabled()
                    ? CallStrings.missedCallNotificationBodyWithoutCallerName
                    : String(format: CallStrings.missedCallNotificationBodyWithCallerName, callerName))
        }}()

        content.body = notificationBody
        content.sound = UNNotificationSound.default()
        content.categoryIdentifier = AppNotifications.category(.missedCall).identifier

        let request = UNNotificationRequest.init(identifier: call.localId.uuidString, content: content, trigger: nil)

        center.add(request)
    }

    public func presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: SignalCall, callerName: String) {
        Logger.debug("")

        let content = UNMutableNotificationContent()
        // TODO group by thread identifier
        // content.threadIdentifier = threadId

        let notificationBody = { () -> String in
            switch previewType {
            case .noNameNoPreview:
                return CallStrings.missedCallWithIdentityChangeNotificationBodyWithoutCallerName
            case .nameNoPreview, .namePreview:
                return (Environment.shared.preferences.isCallKitPrivacyEnabled()
                    ? CallStrings.missedCallWithIdentityChangeNotificationBodyWithoutCallerName
                    : String(format: CallStrings.missedCallWithIdentityChangeNotificationBodyWithCallerName, callerName))
            }}()

        content.body = notificationBody
        content.sound = UNNotificationSound.default()
        content.categoryIdentifier = AppNotifications.category(.missedCallFromNoLongerVerifiedIdentity).identifier

        let request = UNNotificationRequest.init(identifier: call.localId.uuidString, content: content, trigger: nil)

        center.add(request)
    }

    public func presentMissedCallBecauseOfNewIdentity(call: SignalCall, callerName: String) {
        Logger.debug("")

        let content = UNMutableNotificationContent()
        // TODO group by thread identifier
        // content.threadIdentifier = threadId

        let notificationBody = { () -> String in
            switch previewType {
            case .noNameNoPreview:
                return CallStrings.missedCallWithIdentityChangeNotificationBodyWithoutCallerName
            case .nameNoPreview, .namePreview:
                return (Environment.shared.preferences.isCallKitPrivacyEnabled()
                    ? CallStrings.missedCallWithIdentityChangeNotificationBodyWithoutCallerName
                    : String(format: CallStrings.missedCallWithIdentityChangeNotificationBodyWithCallerName, callerName))
            }}()

        content.body = notificationBody
        content.sound = UNNotificationSound.default()
        content.categoryIdentifier = AppNotifications.category(.missedCall).identifier

        let request = UNNotificationRequest.init(identifier: call.localId.uuidString, content: content, trigger: nil)

        center.add(request)
    }
}
