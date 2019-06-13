//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UserNotifications
import PromiseKit

@available(iOS 10.0, *)
class UserNotificationConfig {

    class var allNotificationCategories: Set<UNNotificationCategory> {
        let categories = AppNotificationCategory.allCases.map { notificationCategory($0) }
        return Set(categories)
    }

    class func notificationActions(for category: AppNotificationCategory) -> [UNNotificationAction] {
        return category.actions.map { notificationAction($0) }
    }

    class func notificationCategory(_ category: AppNotificationCategory) -> UNNotificationCategory {
        return UNNotificationCategory(identifier: category.identifier,
                                      actions: notificationActions(for: category),
                                      intentIdentifiers: [],
                                      options: [])
    }

    class func notificationAction(_ action: AppNotificationAction) -> UNNotificationAction {
        switch action {
        case .answerCall:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.answerCallButtonTitle,
                                        options: [.foreground])
        case .callBack:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.callBackButtonTitle,
                                        options: [.foreground])
        case .declineCall:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.declineCallButtonTitle,
                                        options: [])
        case .markAsRead:
            return UNNotificationAction(identifier: action.identifier,
                                        title: MessageStrings.markAsReadNotificationAction,
                                        options: [])
        case .reply:
            return UNTextInputNotificationAction(identifier: action.identifier,
                                                 title: MessageStrings.replyNotificationAction,
                                                 options: [],
                                                 textInputButtonTitle: MessageStrings.sendButton,
                                                 textInputPlaceholder: "")
        case .showThread:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.showThreadButtonTitle,
                                        options: [.foreground])
        }
    }

    class func action(identifier: String) -> AppNotificationAction? {
        return AppNotificationAction.allCases.first { notificationAction($0).identifier == identifier }
    }

}

@available(iOS 10.0, *)
class UserNotificationPresenterAdaptee: NSObject {

    private let notificationCenter: UNUserNotificationCenter
    private var notifications: [String: UNNotificationRequest] = [:]

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
        SwiftSingletons.register(self)
    }
}

@available(iOS 10.0, *)
extension UserNotificationPresenterAdaptee: NotificationPresenterAdaptee {

    func registerNotificationSettings() -> Promise<Void> {
        return Promise { resolver in
            notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
                self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)

                if granted {
                    Logger.debug("succeeded.")
                } else if error != nil {
                    Logger.error("failed with error: \(error!)")
                } else {
                    owsFailDebug("error was unexpectedly nil")
                    Logger.error("failed without error.")
                }

                // Note that the promise is fulfilled regardless of if notification permssions were
                // granted. This promise only indicates that the user has responded, so we can
                // proceed with requesting push tokens and complete registration.
                resolver.fulfill(())
            }
        }
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?) {
        AssertIsOnMainThread()
        notify(category: category, title: title, body: body, threadIdentifier: threadIdentifier, userInfo: userInfo, sound: sound, replacingIdentifier: nil)
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?, replacingIdentifier: String?) {
        AssertIsOnMainThread()

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        let isAppActive = UIApplication.shared.applicationState == .active
        if let sound = sound, sound != OWSSound.none {
            content.sound = sound.notificationSound(isQuiet: isAppActive)
        }

        var notificationIdentifier: String = UUID().uuidString
        if let replacingIdentifier = replacingIdentifier {
            notificationIdentifier = replacingIdentifier
            Logger.debug("replacing notification with identifier: \(notificationIdentifier)")
            cancelNotification(identifier: notificationIdentifier)
        }

        let trigger: UNNotificationTrigger?
        let checkForCancel = category == .incomingMessage
        if checkForCancel && hasReceivedSyncMessageRecently {
            assert(userInfo[AppNotificationUserInfoKey.threadId] != nil)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: kNotificationDelayForRemoteRead, repeats: false)
        } else {
            trigger = nil
        }

        if shouldPresentNotification(category: category, userInfo: userInfo) {
            if let displayableTitle = title?.filterForDisplay {
                content.title = displayableTitle
            }
            if let displayableBody = body.filterForDisplay {
                content.body = displayableBody
            }
        } else {
            // Play sound and vibrate, but without a `body` no banner will show.
            Logger.debug("supressing notification body")
        }

        if let threadIdentifier = threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }

        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)

        Logger.debug("presenting notification with identifier: \(notificationIdentifier)")
        notificationCenter.add(request)
        notifications[notificationIdentifier] = request
    }

    func cancelNotification(identifier: String) {
        AssertIsOnMainThread()
        notifications.removeValue(forKey: identifier)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotification(_ notification: UNNotificationRequest) {
        AssertIsOnMainThread()
        cancelNotification(identifier: notification.identifier)
    }

    func cancelNotifications(threadId: String) {
        AssertIsOnMainThread()
        for notification in notifications.values {
            guard let notificationThreadId = notification.content.userInfo[AppNotificationUserInfoKey.threadId] as? String else {
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
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        LegacyNotificationPresenterAdaptee.clearExistingNotifications()
    }

    func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        AssertIsOnMainThread()
        guard UIApplication.shared.applicationState == .active else {
            return true
        }

        guard category == .incomingMessage || category == .infoOrErrorMessage else {
            return true
        }

        guard let notificationThreadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            owsFailDebug("threadId was unexpectedly nil")
            return true
        }

        guard let conversationViewController = UIApplication.shared.frontmostViewController as? ConversationViewController else {
            return true
        }

        // Show notifications for any *other* thread
        return conversationViewController.thread.uniqueId != notificationThreadId
    }
}

@objc(OWSUserNotificationActionHandler)
@available(iOS 10.0, *)
public class UserNotificationActionHandler: NSObject {

    var actionHandler: NotificationActionHandler {
        return NotificationActionHandler.shared
    }

    @objc
    func handleNotificationResponse( _ response: UNNotificationResponse, completionHandler: @escaping () -> Void) {
        AssertIsOnMainThread()
        firstly {
            try handleNotificationResponse(response)
        }.done {
            completionHandler()
        }.catch { error in
            completionHandler()
            owsFailDebug("error: \(error)")
            Logger.error("error: \(error)")
        }.retainUntilComplete()
    }

    func handleNotificationResponse( _ response: UNNotificationResponse) throws -> Promise<Void> {
        AssertIsOnMainThread()
        assert(AppReadiness.isAppReady())

        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Logger.debug("default action")
            return try actionHandler.showThread(userInfo: userInfo)
        case UNNotificationDismissActionIdentifier:
            // TODO - mark as read?
            Logger.debug("dismissed notification")
            return Promise.value(())
        default:
            // proceed
            break
        }

        guard let action = UserNotificationConfig.action(identifier: response.actionIdentifier) else {
            throw NotificationError.failDebug("unable to find action for actionIdentifier: \(response.actionIdentifier)")
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
            guard let textInputResponse = response as? UNTextInputNotificationResponse else {
                throw NotificationError.failDebug("response had unexpected type: \(response)")
            }

            return try actionHandler.reply(userInfo: userInfo, replyText: textInputResponse.userText)
        case .showThread:
            return try actionHandler.showThread(userInfo: userInfo)
        }
    }
}

extension OWSSound {
    @available(iOS 10.0, *)
    func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = OWSSounds.filename(for: self, quiet: isQuiet) else {
            owsFailDebug("filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}
