//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

struct LegacyNotificationConfig {

    static var allNotificationCategories: Set<UIUserNotificationCategory> {
        let categories = AppNotificationCategory.allCases.map { notificationCategory($0) }
        return Set(categories)
    }

    static func notificationActions(for category: AppNotificationCategory) -> [UIUserNotificationAction] {
        return category.actions.map { notificationAction($0) }
    }

    static func notificationAction(_ action: AppNotificationAction) -> UIUserNotificationAction {
        switch action {
        case .answerCall:
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.identifier = action.identifier
            mutableAction.title = CallStrings.answerCallButtonTitle
            mutableAction.activationMode = .foreground
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = false
            return mutableAction
        case .callBack:
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.identifier = action.identifier
            mutableAction.title = CallStrings.callBackButtonTitle
            mutableAction.activationMode = .foreground
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = true
            return mutableAction
        case .declineCall:
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.identifier = action.identifier
            mutableAction.title = CallStrings.declineCallButtonTitle
            mutableAction.activationMode = .background
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = false
            return mutableAction
        case .markAsRead:
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.identifier = action.identifier
            mutableAction.title = MessageStrings.markAsReadNotificationAction
            mutableAction.activationMode = .background
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = false
            return mutableAction
        case .reply:
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.identifier = action.identifier
            mutableAction.title = MessageStrings.replyNotificationAction
            mutableAction.activationMode = .background
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = false
            mutableAction.behavior = .textInput
            return mutableAction
        case .showThread:
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.identifier = action.identifier
            mutableAction.title = CallStrings.showThreadButtonTitle
            mutableAction.activationMode = .foreground
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = true
            return mutableAction
        }
    }

    static func action(identifier: String) -> AppNotificationAction? {
        return AppNotificationAction.allCases.first { notificationAction($0).identifier == identifier }
    }

    static func notificationActions(category: AppNotificationCategory) -> [UIUserNotificationAction] {
        return category.actions.map { notificationAction($0) }
    }

    static func notificationCategory(_ category: AppNotificationCategory) -> UIUserNotificationCategory {
        let notificationCategory = UIMutableUserNotificationCategory()
        notificationCategory.identifier = category.identifier

        let actions = notificationActions(category: category)
        notificationCategory.setActions(actions, for: .minimal)
        notificationCategory.setActions(actions, for: .default)

        return notificationCategory
    }
}

class LegacyNotificationPresenterAdaptee {

    private var notifications: [String: UILocalNotification] = [:]
    private var userNotificationSettingsPromise: Promise<Void>?
    private var userNotificationSettingsResolver: Resolver<Void>?

    // Notification registration is confirmed via AppDelegate
    // Before this occurs, it is not safe to assume push token requests will be acknowledged.
    //
    // e.g. in the case that Background Fetch is disabled, token requests will be ignored until
    // we register user notification settings.
    @objc
    public func didRegisterUserNotificationSettings() {
        AssertIsOnMainThread()
        guard let userNotificationSettingsResolver = self.userNotificationSettingsResolver else {
            owsFailDebug("promise completion in \(#function) unexpectedly nil")
            return
        }

        userNotificationSettingsResolver.fulfill(())
    }

}

extension LegacyNotificationPresenterAdaptee: NotificationPresenterAdaptee {

    func registerNotificationSettings() -> Promise<Void> {
        AssertIsOnMainThread()
        Logger.debug("")

        guard self.userNotificationSettingsPromise == nil else {
            let promise = self.userNotificationSettingsPromise!
            Logger.info("already registered user notification settings")
            return promise
        }

        let (promise, resolver) = Promise<Void>.pending()
        self.userNotificationSettingsPromise = promise
        self.userNotificationSettingsResolver = resolver

        let settings = UIUserNotificationSettings(types: [.alert, .sound, .badge],
                                                  categories: LegacyNotificationConfig.allNotificationCategories)
        UIApplication.shared.registerUserNotificationSettings(settings)

        return promise
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?) {
        AssertIsOnMainThread()
        notify(category: category, title: title, body: body, threadIdentifier: threadIdentifier, userInfo: userInfo, sound: sound, replacingIdentifier: nil)
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?, replacingIdentifier: String?) {
        AssertIsOnMainThread()
        guard UIApplication.shared.applicationState != .active else {
            if let sound = sound {
                let soundId = OWSSounds.systemSoundID(for: sound, quiet: true)

                // Vibrate, respect silent switch, respect "Alert" volume, not media volume.
                AudioServicesPlayAlertSound(soundId)
            }
            return
        }

        // UILocalNotification strips anything that looks like a printf
        // formatting character from the notification body, so if we want to
        // display a literal "%" in a notification it must be escaped.
        // see https://developer.apple.com/documentation/uikit/uilocalnotification/1616646-alertbody
        // for more details. UNUserNotifications do not require this.
        let escapedBody = body.replacingOccurrences(of: "%", with: "%%")

        let alertBody: String
        if let title = title {
            // TODO - Make this a format string for better l10n
            alertBody = title + ":" + " " + escapedBody
        } else {
            alertBody = escapedBody
        }

        let notification = UILocalNotification()
        notification.category = category.identifier
        notification.alertBody = alertBody.filterForDisplay
        notification.userInfo = userInfo
        notification.soundName = sound?.filename

        var notificationIdentifier: String = UUID().uuidString
        if let replacingIdentifier = replacingIdentifier {
            notificationIdentifier = replacingIdentifier
            Logger.debug("replacing notification with identifier: \(notificationIdentifier)")
            cancelNotification(identifier: notificationIdentifier)
        }

        let checkForCancel = category == .incomingMessage
        if checkForCancel && hasReceivedSyncMessageRecently {
            assert(userInfo[AppNotificationUserInfoKey.threadId] != nil)
            notification.fireDate = Date(timeIntervalSinceNow: kNotificationDelayForRemoteRead)
            notification.timeZone = NSTimeZone.local
        }

        Logger.debug("presenting notification with identifier: \(notificationIdentifier)")
        UIApplication.shared.scheduleLocalNotification(notification)
        notifications[notificationIdentifier] = notification
    }

    func cancelNotification(_ notification: UILocalNotification) {
        AssertIsOnMainThread()
        UIApplication.shared.cancelLocalNotification(notification)
    }

    func cancelNotification(identifier: String) {
        AssertIsOnMainThread()
        guard let notification = notifications.removeValue(forKey: identifier) else {
            Logger.debug("no notification to cancel with identifier: \(identifier)")
            return
        }

        cancelNotification(notification)
    }

    func cancelNotifications(threadId: String) {
        AssertIsOnMainThread()
        for notification in notifications.values {
            guard let notificationThreadId = notification.userInfo?[AppNotificationUserInfoKey.threadId] as? String else {
                continue
            }

            guard notificationThreadId == threadId else {
                continue
            }

            cancelNotification(notification)
        }
    }

    func clearAllNotifications() {
        AssertIsOnMainThread()
        for (_, notification) in notifications {
            cancelNotification(notification)
        }
        type(of: self).clearExistingNotifications()
    }

    public class func clearExistingNotifications() {
        // This will cancel all "scheduled" local notifications that haven't
        // been presented yet.
        UIApplication.shared.cancelAllLocalNotifications()
        // To clear all already presented local notifications, we need to
        // set the app badge number to zero after setting it to a non-zero value.
        UIApplication.shared.applicationIconBadgeNumber = 1
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}

@objc(OWSLegacyNotificationActionHandler)
public class LegacyNotificationActionHandler: NSObject {

    @objc
    public static let kDefaultActionIdentifier = "LegacyNotificationActionHandler.kDefaultActionIdentifier"

    var actionHandler: NotificationActionHandler {
        return NotificationActionHandler.shared
    }

    @objc
    func handleNotificationResponse(actionIdentifier: String,
                                    notification: UILocalNotification,
                                    responseInfo: [AnyHashable: Any],
                                    completionHandler: @escaping () -> Void) {
        firstly {
            try handleNotificationResponse(actionIdentifier: actionIdentifier, notification: notification, responseInfo: responseInfo)
        }.done {
            completionHandler()
        }.catch { error in
            completionHandler()
            owsFailDebug("error: \(error)")
            Logger.error("error: \(error)")
        }.retainUntilComplete()
    }

    func handleNotificationResponse(actionIdentifier: String,
                                    notification: UILocalNotification,
                                    responseInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        assert(AppReadiness.isAppReady())

        let userInfo = notification.userInfo ?? [:]

        switch actionIdentifier {
        case type(of: self).kDefaultActionIdentifier:
            Logger.debug("default action")
            return try actionHandler.showThread(userInfo: userInfo)
        default:
            // proceed
            break
        }

        guard let action = LegacyNotificationConfig.action(identifier: actionIdentifier) else {
            throw NotificationError.failDebug("unable to find action for actionIdentifier: \(actionIdentifier)")
        }

        switch action {
        case .answerCall:
            return try actionHandler.answerCall(userInfo: userInfo)
        case .callBack:
            return try actionHandler.callBack(userInfo: userInfo)
        case .declineCall:
            return try actionHandler.declineCall(userInfo: userInfo)
        case .markAsRead:
            return try actionHandler.markAsRead(userInfo: userInfo)
        case .reply:
            guard let replyText = responseInfo[UIUserNotificationActionResponseTypedTextKey] as? String else {
                throw NotificationError.failDebug("replyText was unexpectedly nil")
            }

            return try actionHandler.reply(userInfo: userInfo, replyText: replyText)
        case .showThread:
            return try actionHandler.showThread(userInfo: userInfo)
        }
    }
}

extension OWSSound {
    var filename: String? {
        return OWSSounds.filename(for: self, quiet: false)
    }
}
