//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UserNotifications
import PromiseKit

public class UserNotificationConfig {

    class var allNotificationCategories: Set<UNNotificationCategory> {
        let categories = AppNotificationCategory.allCases.map { notificationCategory($0) }
        return Set(categories)
    }

    class func notificationActions(for category: AppNotificationCategory) -> [UNNotificationAction] {
        return category.actions.compactMap { notificationAction($0) }
    }

    class func notificationCategory(_ category: AppNotificationCategory) -> UNNotificationCategory {
        return UNNotificationCategory(identifier: category.identifier,
                                      actions: notificationActions(for: category),
                                      intentIdentifiers: [],
                                      options: [])
    }

    class func notificationAction(_ action: AppNotificationAction) -> UNNotificationAction? {
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
        case .reactWithThumbsUp:
            return UNNotificationAction(identifier: action.identifier,
                                        title: MessageStrings.reactWithThumbsUpNotificationAction,
                                        options: [])

        case .showCallLobby:
            // Currently, .showCallLobby is only used as a default action.
            owsFailDebug("Show call lobby not supported as a UNNotificationAction")
            return nil
        }
    }

    public class func action(identifier: String) -> AppNotificationAction? {
        return AppNotificationAction.allCases.first { notificationAction($0)?.identifier == identifier }
    }

}

class UserNotificationPresenterAdaptee: NSObject, NotificationPresenterAdaptee {

    private let notificationCenter: UNUserNotificationCenter

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
        SwiftSingletons.register(self)
    }

    func registerNotificationSettings() -> Promise<Void> {
        return Promise { resolver in
            notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
                self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)

                if granted {
                    Logger.debug("succeeded.")
                } else if error != nil {
                    Logger.error("failed with error: \(error!)")
                } else {
                    Logger.info("failed without error. User denied notification permissions.")
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

        guard tsAccountManager.isOnboarded() else {
            Logger.info("suppressing notification since user hasn't yet completed onboarding.")
            return
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        let isAppActive = CurrentAppContext().isMainAppAndActive
        if let sound = sound, sound != OWSStandardSound.none.rawValue {
            content.sound = sound.notificationSound(isQuiet: isAppActive)
        }

        var notificationIdentifier: String = UUID().uuidString
        if let replacingIdentifier = replacingIdentifier {
            notificationIdentifier = replacingIdentifier
            Logger.debug("replacing notification with identifier: \(notificationIdentifier)")
            cancelNotification(identifier: notificationIdentifier)
        }

        let trigger: UNNotificationTrigger?
        let checkForCancel = (category == .incomingMessageWithActions_CanReply ||
                                category == .incomingMessageWithActions_CannotReply ||
                                category == .incomingMessageWithoutActions ||
                                category == .incomingReactionWithActions_CanReply ||
                                category == .incomingReactionWithActions_CannotReply)
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
        notificationCenter.add(request) { (error: Error?) in
            if let error = error {
                owsFailDebug("Error: \(error)")
                return
            }
        }
    }

    private var pendingCancelations = Set<PendingCancelation>() {
        didSet {
            AssertIsOnMainThread()
            guard !pendingCancelations.isEmpty else { return }
            drainCancelations()
        }
    }
    private enum PendingCancelation: Equatable, Hashable {
        case threadId(String)
        case messageId(String)
        case reactionId(String)
    }

    private var isDrainingCancelations = false
    private func drainCancelations() {
        AssertIsOnMainThread()

        guard !isDrainingCancelations, !pendingCancelations.isEmpty else { return }
        isDrainingCancelations = true

        getNotificationRequests().done(on: .main) { requests in
            requestLoop:
            for request in requests {
                for cancelation in self.pendingCancelations {
                    switch cancelation {
                    case .threadId(let threadId):
                        let requestThreadId = request.content.userInfo[AppNotificationUserInfoKey.threadId] as? String
                        if threadId == requestThreadId {
                            self.cancelNotification(request)
                            self.pendingCancelations.remove(cancelation)
                            continue requestLoop
                        }
                    case .messageId(let messageId):
                        let requestMessageId = request.content.userInfo[AppNotificationUserInfoKey.messageId] as? String
                        if messageId == requestMessageId {
                            self.cancelNotification(request)
                            self.pendingCancelations.remove(cancelation)
                            continue requestLoop
                        }
                    case .reactionId(let reactionId):
                        let requestReactionId = request.content.userInfo[AppNotificationUserInfoKey.reactionId] as? String
                        if reactionId == requestReactionId {
                            self.cancelNotification(request)
                            self.pendingCancelations.remove(cancelation)
                            continue requestLoop
                        }
                    }
                }
            }

            self.isDrainingCancelations = false

            // Remove anything lingering that didn't match a request,
            // we've checked all the requests.
            self.pendingCancelations.removeAll()
        }
    }

    func cancelNotification(identifier: String) {
        AssertIsOnMainThread()
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotification(_ notification: UNNotificationRequest) {
        AssertIsOnMainThread()

        cancelNotification(identifier: notification.identifier)
    }

    func cancelNotifications(threadId: String) {
        AssertIsOnMainThread()

        pendingCancelations.insert(.threadId(threadId))
    }

    func cancelNotifications(messageId: String) {
        AssertIsOnMainThread()

        pendingCancelations.insert(.messageId(messageId))
    }

    func cancelNotifications(reactionId: String) {
        AssertIsOnMainThread()

        pendingCancelations.insert(.reactionId(reactionId))
    }

    func clearAllNotifications() {
        AssertIsOnMainThread()

        pendingCancelations.removeAll()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        AssertIsOnMainThread()
        guard CurrentAppContext().isMainAppAndActive else {
            return true
        }

        switch category {
        case .incomingMessageWithActions_CanReply,
             .incomingMessageWithActions_CannotReply,
             .incomingMessageWithoutActions,
             .incomingReactionWithActions_CanReply,
             .incomingReactionWithActions_CannotReply,
             .infoOrErrorMessage:
            // If the app is in the foreground, show these notifications
            // unless the corresponding conversation is already open.
            break
        case .incomingMessageFromNoLongerVerifiedIdentity,
             .threadlessErrorMessage,
             .incomingCall,
             .missedCallWithActions,
             .missedCallWithoutActions,
             .missedCallFromNoLongerVerifiedIdentity:
            // Always show these notifications whenever the app is in the foreground.
            return true
        }

        guard let notificationThreadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            owsFailDebug("threadId was unexpectedly nil")
            return true
        }

        guard let conversationSplitVC = CurrentAppContext().frontmostViewController() as? ConversationSplit else {
            return true
        }

        // Show notifications for any *other* thread than the currently selected thread
        return conversationSplitVC.visibleThread?.uniqueId != notificationThreadId
    }

    func getNotificationRequests() -> Guarantee<[UNNotificationRequest]> {
        return getDeliveredNotifications().then { delivered in
            self.getPendingNotificationRequests().map { pending in
                pending + delivered.map { $0.request }
            }
        }
    }

    func getDeliveredNotifications() -> Guarantee<[UNNotification]> {
        return Guarantee { resolver in
            self.notificationCenter.getDeliveredNotifications { resolver($0) }
        }
    }

    func getPendingNotificationRequests() -> Guarantee<[UNNotificationRequest]> {
        return Guarantee { resolver in
            self.notificationCenter.getPendingNotificationRequests { resolver($0) }
        }
    }
}

public protocol ConversationSplit {
    var visibleThread: TSThread? { get }
}

extension OWSSound {
    func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = OWSSounds.filename(forSound: self, quiet: isQuiet) else {
            owsFailDebug("filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}
