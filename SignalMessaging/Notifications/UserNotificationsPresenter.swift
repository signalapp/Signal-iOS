//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications
import Intents
import SignalServiceKit

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
            return notificationActionWithIdentifier(action.identifier,
                                                    title: CallStrings.answerCallButtonTitle,
                                                    options: [.foreground],
                                                    systemImage: "phone")
        case .callBack:
            return notificationActionWithIdentifier(action.identifier,
                                                    title: CallStrings.callBackButtonTitle,
                                                    options: [.foreground],
                                                    systemImage: "phone")
        case .declineCall:
            return notificationActionWithIdentifier(action.identifier,
                                                    title: CallStrings.declineCallButtonTitle,
                                                    options: [],
                                                    systemImage: "phone.down")
        case .markAsRead:
            return notificationActionWithIdentifier(action.identifier,
                                                    title: MessageStrings.markAsReadNotificationAction,
                                                    options: [],
                                                    systemImage: "message")
        case .reply:
            return textInputNotificationActionWithIdentifier(action.identifier,
                                                             title: MessageStrings.replyNotificationAction,
                                                             options: [],
                                                             textInputButtonTitle: MessageStrings.sendButton,
                                                             textInputPlaceholder: "",
                                                             systemImage: "arrowshape.turn.up.left")
        case .showThread:
            return notificationActionWithIdentifier(action.identifier,
                                                    title: CallStrings.showThreadButtonTitle,
                                                    options: [],
                                                    systemImage: "bubble.left.and.bubble.right")
        case .showMyStories:
            // Currently, .showMyStories is only used as a default action.
            owsFailDebug("Show my stories not supported as a UNNotificationAction")
            return nil
        case .reactWithThumbsUp:
            return notificationActionWithIdentifier(action.identifier,
                                                    title: MessageStrings.reactWithThumbsUpNotificationAction,
                                                    options: [],
                                                    systemImage: "hand.thumbsup")
        case .showCallLobby:
            // Currently, .showCallLobby is only used as a default action.
            owsFailDebug("Show call lobby not supported as a UNNotificationAction")
            return nil
        case .submitDebugLogs:
            // Currently, .submitDebugLogs is only used as a default action.
            owsFailDebug("Show submit debug logs not supported as a UNNotificationAction")
            return nil
        case .reregister:
            // Currently, .reregister is only used as a default action.
            owsFailDebug("Reregister is not supported as a UNNotificationAction")
            return nil
        case .showChatList:
            // Currently, .showChatList is only used as a default action.
            owsFailDebug("ShowChatList is not supported as a UNNotificationAction")
            return nil
        }
    }

    private class func notificationActionWithIdentifier(
        _ identifier: String,
        title: String,
        options: UNNotificationActionOptions,
        systemImage: String?) -> UNNotificationAction {
        if #available(iOS 15, *), let systemImage = systemImage {
            let actionIcon = UNNotificationActionIcon(systemImageName: systemImage)
            return UNNotificationAction(identifier: identifier,
                                        title: title,
                                        options: options,
                                        icon: actionIcon)
        } else {
            return UNNotificationAction(identifier: identifier,
                                        title: title,
                                        options: options)
        }
    }

    private class func textInputNotificationActionWithIdentifier(
        _ identifier: String,
        title: String,
        options: UNNotificationActionOptions,
        textInputButtonTitle: String,
        textInputPlaceholder: String,
        systemImage: String?) -> UNNotificationAction {
        if #available(iOS 15, *), let systemImage = systemImage {
            let actionIcon = UNNotificationActionIcon(systemImageName: systemImage)
            return UNTextInputNotificationAction(identifier: identifier,
                                                 title: title,
                                                 options: options,
                                                 icon: actionIcon,
                                                 textInputButtonTitle: textInputButtonTitle,
                                                 textInputPlaceholder: textInputPlaceholder)
        } else {
            return UNTextInputNotificationAction(identifier: identifier,
                                                 title: title,
                                                 options: options,
                                                 textInputButtonTitle: textInputButtonTitle,
                                                 textInputPlaceholder: textInputPlaceholder)
        }
    }

    public class func action(identifier: String) -> AppNotificationAction? {
        return AppNotificationAction.allCases.first { notificationAction($0)?.identifier == identifier }
    }

}

// MARK: -

class UserNotificationPresenter: Dependencies {
    typealias NotificationActionCompletion = () -> Void
    typealias NotificationReplaceCompletion = (Bool) -> Void

    private static var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    // Delay notification of incoming messages when it's likely to be read by a linked device to
    // avoid notifying a user on their phone while a conversation is actively happening on desktop.
    let kNotificationDelayForRemoteRead: TimeInterval = 20

    private let notifyQueue: DispatchQueue

    init(notifyQueue: DispatchQueue) {
        self.notifyQueue = notifyQueue
        SwiftSingletons.register(self)
    }

    /// Request notification permissions.
    func registerNotificationSettings() -> Guarantee<Void> {
        return Guarantee { done in
            Self.notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
                Self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)

                if granted {
                    Logger.info("User granted notification permission")
                } else if let error {
                    owsFailDebug("Notification permission request failed with error: \(error)")
                } else {
                    Logger.info("User denied notification permission")
                }

                done(())
            }
        }
    }

    // MARK: - Notify

    func notify(
        category: AppNotificationCategory,
        title: String?,
        body: String,
        threadIdentifier: String?,
        userInfo: [AnyHashable: Any],
        interaction: INInteraction?,
        sound: Sound?,
        replacingIdentifier: String? = nil,
        forceBeforeRegistered: Bool = false,
        completion: NotificationActionCompletion?
    ) {
        dispatchPrecondition(condition: .onQueue(notifyQueue))

        guard forceBeforeRegistered || DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.info("suppressing notification since user hasn't yet completed registration.")
            completion?()
            return
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        let isAppActive = CurrentAppContext().isMainAppAndActive
        if let sound, sound != .standard(.none) {
            Logger.info("[Notification Sounds] presenting notification with sound")
            content.sound = sound.notificationSound(isQuiet: isAppActive)
        } else {
            Logger.info("[Notification Sounds] presenting notification without sound")
        }

        var notificationIdentifier: String = UUID().uuidString
        if let replacingIdentifier = replacingIdentifier {
            notificationIdentifier = replacingIdentifier
            Logger.debug("replacing notification with identifier: \(notificationIdentifier)")
            cancelNotificationSync(identifier: notificationIdentifier)
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
            content.body = body.filterForDisplay
        } else {
            // Play sound and vibrate, but without a `body` no banner will show.
            Logger.debug("suppressing notification body")
        }

        if let threadIdentifier = threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }

        var contentToUse: UNNotificationContent = content
        if #available(iOS 15, *), let interaction = interaction {
            if DebugFlags.internalLogging {
                Logger.info("Will donate interaction")
            }

            interaction.donate(completion: { error in
                if DebugFlags.internalLogging { Logger.info("Did donate interaction") }

                if let error = error {
                    owsFailDebug("Failed to donate incoming message intent \(error)")
                    return
                }
            })

            if DebugFlags.internalLogging {
                Logger.info("Will update notification content with intent")
            }

            if let intent = interaction.intent as? UNNotificationContentProviding {
                do {
                    try contentToUse = content.updating(from: intent)
                    if DebugFlags.internalLogging {
                        Logger.info("Did update notification content with intent")
                    }
                } catch {
                    owsFailDebug("Failed to update UNNotificationContent for comm style notification")
                }
            }
        }

        let request = UNNotificationRequest(identifier: notificationIdentifier, content: contentToUse, trigger: trigger)

        Logger.info("Presenting notification with identifier \(notificationIdentifier)")
        Self.notificationCenter.add(request) { (error: Error?) in
            if let error = error {
                owsFailDebug("Error presenting notification with identifier \(notificationIdentifier): \(error)")
            } else {
                Logger.info("Presented notification with identifier \(notificationIdentifier)")
            }

            completion?()
        }
    }

    // This method is thread-safe.
    func postGenericIncomingMessageNotification() -> Promise<Void> {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = AppNotificationCategory.incomingMessageGeneric.identifier
        content.userInfo = [:]
        // We use a fixed identifier so that if we post multiple "generic"
        // notifications, they replace each other.
        let notificationIdentifier = "org.signal.genericIncomingMessageNotification"
        content.body = NotificationStrings.genericIncomingMessageNotification
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: nil)

        Logger.info("Presenting generic incoming message notification with identifier \(notificationIdentifier)")

        let (promise, future) = Promise<Void>.pending()
        Self.notificationCenter.add(request) { (error: Error?) in
            if let error = error {
                owsFailDebug("Error presenting generic incoming message notification with identifier \(notificationIdentifier): \(error)")
            } else {
                Logger.info("Presented notification with identifier \(notificationIdentifier)")
            }

            future.resolve(())
        }

        return promise
    }

    private func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        switch category {
        case .incomingMessageFromNoLongerVerifiedIdentity,
             .incomingCall,
             .missedCallWithActions,
             .missedCallWithoutActions,
             .missedCallFromNoLongerVerifiedIdentity,
             .transferRelaunch,
             .deregistration:
            // Always show these notifications
            return true
        case .internalError:
            // Only show errors alerts on builds run by a test population (beta, internal, etc.)
            return DebugFlags.testPopulationErrorAlerts
        case .incomingMessageWithActions_CanReply,
             .incomingMessageWithActions_CannotReply,
             .incomingMessageWithoutActions,
             .incomingReactionWithActions_CanReply,
             .incomingReactionWithActions_CannotReply,
             .infoOrErrorMessage:
            // Only show these notification if:
            // - The app is not foreground
            // - The app is foreground, but the corresponding conversation is not open
            guard CurrentAppContext().isMainAppAndActive else { return true }
            guard let notificationThreadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
                owsFailDebug("threadId was unexpectedly nil")
                return true
            }

            guard let conversationSplitVC = CurrentAppContext().frontmostViewController() as? ConversationSplit else {
                return true
            }

            // Show notifications for any *other* thread than the currently selected thread
            return conversationSplitVC.visibleThread?.uniqueId != notificationThreadId
        case .incomingGroupStoryReply:
            guard StoryManager.areStoriesEnabled else { return false }

            guard CurrentAppContext().isMainAppAndActive else { return true }

            guard let notificationThreadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
                owsFailDebug("threadId was unexpectedly nil")
                return true
            }

            guard let notificationStoryTimestamp = userInfo[AppNotificationUserInfoKey.storyTimestamp] as? UInt64 else {
                owsFailDebug("storyTimestamp was unexpectedly nil")
                return true
            }

            guard let storyGroupReply = CurrentAppContext().frontmostViewController() as? StoryGroupReplier else {
                return true
            }

            // Show notifications any time we're not currently showing the group reply sheet for that story
            return notificationStoryTimestamp != storyGroupReply.storyMessage.timestamp
                || notificationThreadId != storyGroupReply.threadUniqueId
        case .failedStorySend:
            guard StoryManager.areStoriesEnabled else { return false }

            guard CurrentAppContext().isMainAppAndActive else { return true }

            // Show notifications any time we're not currently showing the my stories screen.
            return !(CurrentAppContext().frontmostViewController() is FailedStorySendDisplayController)
        case .incomingMessageGeneric:
            owsFailDebug(".incomingMessageGeneric should never check shouldPresentNotification().")
            return true

        }
    }

    // MARK: - Replacement

    func replaceNotification(messageId: String, completion: @escaping NotificationReplaceCompletion) {
        getNotificationsRequests { requests in
            let didFindNotification = self.cancelSync(
                notificationRequests: requests,
                matching: .messageIds([messageId])
            )
            completion(didFindNotification)
        }
    }

    // MARK: - Cancellation

    func cancelNotifications(threadId: String, completion: @escaping NotificationActionCompletion) {
        cancel(cancellation: .threadId(threadId), completion: completion)
    }

    func cancelNotifications(messageIds: [String], completion: @escaping NotificationActionCompletion) {
        cancel(cancellation: .messageIds(Set(messageIds)), completion: completion)
    }

    func cancelNotifications(reactionId: String, completion: @escaping NotificationActionCompletion) {
        cancel(cancellation: .reactionId(reactionId), completion: completion)
    }

    func cancelNotificationsForMissedCalls(withThreadUniqueId threadId: String, completion: @escaping NotificationActionCompletion) {
        cancel(cancellation: .missedCalls(inThreadWithUniqueId: threadId), completion: completion)
    }

    func cancelNotificationsForStoryMessage(withUniqueId storyMessageUniqueId: String, completion: @escaping NotificationActionCompletion) {
        cancel(cancellation: .storyMessage(storyMessageUniqueId), completion: completion)
    }

    func clearAllNotifications() {
        Logger.warn("Clearing all notifications")

        Self.notificationCenter.removeAllPendingNotificationRequests()
        Self.notificationCenter.removeAllDeliveredNotifications()
    }

    private enum CancellationType: Equatable, Hashable {
        case threadId(String)
        case messageIds(Set<String>)
        case reactionId(String)
        case missedCalls(inThreadWithUniqueId: String)
        case storyMessage(String)
    }

    private func getNotificationsRequests(completion: @escaping ([UNNotificationRequest]) -> Void) {
        Self.notificationCenter.getDeliveredNotifications { delivered in
            Self.notificationCenter.getPendingNotificationRequests { pending in
                completion(delivered.map { $0.request } + pending)
            }
        }
    }

    private func cancel(
        cancellation: CancellationType,
        completion: @escaping NotificationActionCompletion
    ) {
        getNotificationsRequests { requests in
            self.cancelSync(notificationRequests: requests, matching: cancellation)
            completion()
        }
    }

    @discardableResult
    private func cancelSync(
        notificationRequests: [UNNotificationRequest],
        matching cancellationType: CancellationType
    ) -> Bool {
        let requestMatchesPredicate: (UNNotificationRequest) -> Bool = { request in
            switch cancellationType {
            case .threadId(let threadId):
                if
                    let requestThreadId = request.content.userInfo[AppNotificationUserInfoKey.threadId] as? String,
                    requestThreadId == threadId
                {
                    return true
                }
            case .messageIds(let messageIds):
                if
                    let requestMessageId = request.content.userInfo[AppNotificationUserInfoKey.messageId] as? String,
                    messageIds.contains(requestMessageId)
                {
                    return true
                }
            case .reactionId(let reactionId):
                if
                    let requestReactionId = request.content.userInfo[AppNotificationUserInfoKey.reactionId] as? String,
                    requestReactionId == reactionId
                {
                    return true
                }
            case .missedCalls(let threadUniqueId):
                if
                    (request.content.userInfo[AppNotificationUserInfoKey.isMissedCall] as? Bool) == true,
                    let requestThreadId = request.content.userInfo[AppNotificationUserInfoKey.threadId] as? String,
                    threadUniqueId == requestThreadId
                {
                    return true
                }
            case .storyMessage(let storyMessageUniqueId):
                if
                    let requestStoryMessageId = request.content.userInfo[AppNotificationUserInfoKey.storyMessageId] as? String,
                    requestStoryMessageId == storyMessageUniqueId
                {
                    return true
                }
            }

            return false
        }

        let identifiersToCancel: [String] = {
            notificationRequests.compactMap { request in
                if requestMatchesPredicate(request) {
                    return request.identifier
                }

                return nil
            }
        }()

        guard !identifiersToCancel.isEmpty else {
            return false
        }

        Logger.info("Removing delivered/pending notifications with identifiers: \(identifiersToCancel)")

        Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToCancel)
        Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)

        return true
    }

    // This method is thread-safe.
    private func cancelNotificationSync(identifier: String) {
        Logger.warn("Canceling notification for identifier: \(identifier)")

        Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

public protocol ConversationSplit {
    var visibleThread: TSThread? { get }
}

public protocol StoryGroupReplier: UIViewController {
    var storyMessage: StoryMessage { get }
    var threadUniqueId: String? { get }
}

extension Sound {
    func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = filename(quiet: isQuiet) else {
            owsFailDebug("[Notification Sounds] sound filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        if
            !FileManager.default.fileExists(atPath: (Sounds.soundsDirectory as NSString).appendingPathComponent(filename))
            && !FileManager.default.fileExists(atPath: (Bundle.main.bundlePath as NSString).appendingPathComponent(filename))
        {
            Logger.info("[Notification Sounds] sound file doesn't exist!")
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}

extension UNAuthorizationStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default:
            owsFailDebug("New case! Please update the method")
            return "Raw value: \(rawValue)"
        }
    }
}
