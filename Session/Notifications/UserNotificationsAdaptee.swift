//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UserNotifications
import PromiseKit
import SessionMessagingKit

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

class UserNotificationPresenterAdaptee: NSObject, UNUserNotificationCenterDelegate {

    private let notificationCenter: UNUserNotificationCenter
    private var notifications: [String: UNNotificationRequest] = [:]

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        
        super.init()
        
        SwiftSingletons.register(self)
    }
}

extension UserNotificationPresenterAdaptee: NotificationPresenterAdaptee {

    func registerNotificationSettings() -> Promise<Void> {
        return Promise { resolver in
            notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
                self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)

                if granted {
                    
                } else if error != nil {
                    Logger.error("failed with error: \(error!)")
                } else {
                    Logger.error("failed without error.")
                }

                // Note that the promise is fulfilled regardless of if notification permssions were
                // granted. This promise only indicates that the user has responded, so we can
                // proceed with requesting push tokens and complete registration.
                resolver.fulfill(())
            }
        }
    }

    func notify(
        category: AppNotificationCategory,
        title: String?,
        body: String,
        userInfo: [AnyHashable: Any],
        previewType: Preferences.NotificationPreviewType,
        sound: Preferences.Sound?,
        threadVariant: SessionThread.Variant,
        threadName: String,
        replacingIdentifier: String?
    ) {
        AssertIsOnMainThread()

        let threadIdentifier: String? = (userInfo[AppNotificationUserInfoKey.threadId] as? String)
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        content.threadIdentifier = (threadIdentifier ?? content.threadIdentifier)
        
        let shouldGroupNotification: Bool = (
            threadVariant == .openGroup &&
            replacingIdentifier == threadIdentifier
        )
        let isAppActive = UIApplication.shared.applicationState == .active
        if let sound = sound, sound != .none {
            content.sound = sound.notificationSound(isQuiet: isAppActive)
        }
        
        let notificationIdentifier: String = (replacingIdentifier ?? UUID().uuidString)
        let isReplacingNotification: Bool = (notifications[notificationIdentifier] != nil)
        var trigger: UNNotificationTrigger?

        if shouldPresentNotification(category: category, userInfo: userInfo) {
            if let displayableTitle = title?.filterForDisplay {
                content.title = displayableTitle
            }
            if let displayableBody = body.filterForDisplay {
                content.body = displayableBody
            }
            
            if shouldGroupNotification {
                trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: Notifications.delayForGroupedNotifications,
                    repeats: false
                )
                
                let numberExistingNotifications: Int? = notifications[notificationIdentifier]?
                    .content
                    .userInfo[AppNotificationUserInfoKey.threadNotificationCounter]
                    .asType(Int.self)
                var numberOfNotifications: Int = (numberExistingNotifications ?? 1)
                
                if numberExistingNotifications != nil {
                    numberOfNotifications += 1  // Add one for the current notification
                    
                    content.title = (previewType == .noNameNoPreview ?
                        content.title :
                        threadName
                    )
                    content.body = String(
                        format: NotificationStrings.incomingCollapsedMessagesBody,
                        "\(numberOfNotifications)"
                    )
                }
                
                content.userInfo[AppNotificationUserInfoKey.threadNotificationCounter] = numberOfNotifications
            }
        }
        else {
            // Play sound and vibrate, but without a `body` no banner will show.
            Logger.debug("supressing notification body")
        }

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        Logger.debug("presenting notification with identifier: \(notificationIdentifier)")
        
        if isReplacingNotification { cancelNotifications(identifiers: [notificationIdentifier]) }
        
        notificationCenter.add(request)
        notifications[notificationIdentifier] = request
    }

    func cancelNotifications(identifiers: [String]) {
        AssertIsOnMainThread()
        identifiers.forEach { notifications.removeValue(forKey: $0) }
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelNotification(_ notification: UNNotificationRequest) {
        AssertIsOnMainThread()
        cancelNotifications(identifiers: [notification.identifier])
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
    }

    func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        AssertIsOnMainThread()
        guard UIApplication.shared.applicationState == .active else {
            return true
        }

        guard category == .incomingMessage || category == .errorMessage else {
            return true
        }

        guard let notificationThreadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            owsFailDebug("threadId was unexpectedly nil")
            return true
        }
        
        guard let conversationViewController = UIApplication.shared.frontmostViewController as? ConversationVC else {
            return true
        }
        
        /// Show notifications for any **other** threads
        return (conversationViewController.viewModel.threadData.threadId != notificationThreadId)
    }
}

@objc(OWSUserNotificationActionHandler)
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
