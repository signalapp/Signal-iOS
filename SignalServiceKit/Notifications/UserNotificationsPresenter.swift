//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Intents
import UserNotifications

public class UserNotificationConfig {

    class var allNotificationCategories: Set<UNNotificationCategory> {
        let categories = AppNotificationCategory.allCases.map { notificationCategory($0) }
        return Set(categories)
    }

    class func notificationActions(for category: AppNotificationCategory) -> [UNNotificationAction] {
        return category.actions.compactMap { notificationAction($0) }
    }

    class func notificationCategory(_ category: AppNotificationCategory) -> UNNotificationCategory {
        return UNNotificationCategory(
            identifier: category.identifier,
            actions: notificationActions(for: category),
            intentIdentifiers: [],
            options: []
        )
    }

    class func notificationAction(_ action: AppNotificationAction) -> UNNotificationAction? {
        switch action {
        case .callBack:
            return UNNotificationAction(
                identifier: action.identifier,
                title: CallStrings.callBackButtonTitle,
                options: .foreground,
                icon: UNNotificationActionIcon(systemImageName: "phone")
            )
        case .markAsRead:
            return UNNotificationAction(
                identifier: action.identifier,
                title: MessageStrings.markAsReadNotificationAction,
                icon: UNNotificationActionIcon(systemImageName: "message")
            )
        case .reply:
            return UNTextInputNotificationAction(
                identifier: action.identifier,
                title: MessageStrings.replyNotificationAction,
                icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
                textInputButtonTitle: MessageStrings.sendButton,
                textInputPlaceholder: ""
            )
        case .showThread:
            return UNNotificationAction(
                identifier: action.identifier,
                title: CallStrings.showThreadButtonTitle,
                icon: UNNotificationActionIcon(systemImageName: "bubble.left.and.bubble.right")
            )
        case .showMyStories:
            // Currently, .showMyStories is only used as a default action.
            owsFailDebug("Show my stories not supported as a UNNotificationAction")
            return nil
        case .reactWithThumbsUp:
            return UNNotificationAction(
                identifier: action.identifier,
                title: MessageStrings.reactWithThumbsUpNotificationAction,
                icon: UNNotificationActionIcon(systemImageName: "hand.thumbsup")
            )
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
        case .showLinkedDevices:
            // Currently, .showLinkedDevices is only used as a default action.
            owsFailDebug("showLinkedDevices is not supported as a UNNotificationAction")
            return nil
        }
    }

    public class func action(identifier: String) -> AppNotificationAction? {
        return AppNotificationAction.allCases.first { notificationAction($0)?.identifier == identifier }
    }
}

// MARK: -

class UserNotificationPresenter {
    private static var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    // Delay notification of incoming messages when it's likely to be read by a linked device to
    // avoid notifying a user on their phone while a conversation is actively happening on desktop.
    let kNotificationDelayForRemoteRead: TimeInterval = 20

    init() {
        SwiftSingletons.register(self)
    }

    /// Request notification permissions.
    func registerNotificationSettings() async {
        do {
            let granted = try await Self.notificationCenter.requestAuthorization(options: [.badge, .sound, .alert])
            Logger.info("Notification permission? \(granted)")
        } catch {
            owsFailDebug("Notification permission request failed with error: \(error)")
        }
        Self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)
    }

    var hasReceivedSyncMessageRecentlyWithSneakyTransaction: Bool {
        let db = DependenciesBridge.shared.db
        let deviceManager = DependenciesBridge.shared.deviceManager
        return db.read { tx in
            return deviceManager.hasReceivedSyncMessage(inLastSeconds: 60, transaction: tx)
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
        isMainAppAndActive: Bool,
        notificationSuppressionRule: NotificationSuppressionRule
    ) async {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        // TODO: It might make sense to have the callers check this instead. Further investigation is required.
        guard forceBeforeRegistered || tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.info("suppressing notification since user hasn't yet completed registration.")
            return
        }
        // TODO: It might make sense to have the callers check this instead. Further investigation is required.
        if case .incomingGroupStoryReply = category, !StoryManager.areStoriesEnabled {
            return
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        if let sound, sound != .standard(.none) {
            content.sound = sound.notificationSound(isQuiet: isMainAppAndActive)
        }

        var notificationIdentifier: String = UUID().uuidString
        if let replacingIdentifier {
            notificationIdentifier = replacingIdentifier
            Logger.debug("replacing notification with identifier: \(notificationIdentifier)")
            cancelNotificationSync(identifier: notificationIdentifier)
        }

        let trigger: UNNotificationTrigger?
        let checkForCancel = (
            category == .incomingMessageWithActions_CanReply
            || category == .incomingMessageWithActions_CannotReply
            || category == .incomingMessageWithoutActions
            || category == .incomingReactionWithActions_CanReply
            || category == .incomingReactionWithActions_CannotReply
        )
        if checkForCancel, !isMainAppAndActive, hasReceivedSyncMessageRecentlyWithSneakyTransaction {
            assert(userInfo[AppNotificationUserInfoKey.threadId] != nil)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: kNotificationDelayForRemoteRead, repeats: false)
        } else if category == .newDeviceLinked {
            let delay = TimeInterval.random(in: kHourInterval...(kHourInterval * 3))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        } else {
            trigger = nil
        }

        if shouldPresentNotification(category: category, userInfo: userInfo, notificationSuppressionRule: notificationSuppressionRule) {
            if let displayableTitle = title?.filterForDisplay {
                content.title = displayableTitle
            }
            content.body = body.filterForDisplay
        } else {
            // Play sound and vibrate, but without a `body` no banner will show.
        }

        if let threadIdentifier = threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }

        var contentToUse: UNNotificationContent = content
        if let interaction {
            do {
                try await interaction.donate()
            } catch {
                owsFailDebug("Failed to donate incoming message intent \(error)")
            }

            if let intent = interaction.intent as? UNNotificationContentProviding {
                do {
                    contentToUse = try content.updating(from: intent)
                } catch {
                    owsFailDebug("Failed to update UNNotificationContent for comm style notification")
                }
            }
        }

        let request = UNNotificationRequest(identifier: notificationIdentifier, content: contentToUse, trigger: trigger)

        do {
            try await Self.notificationCenter.add(request)
        } catch {
            owsFailDebug("Error presenting notification with identifier \(notificationIdentifier): \(error)")
        }
    }

    private func shouldPresentNotification(
        category: AppNotificationCategory,
        userInfo: [AnyHashable: Any],
        notificationSuppressionRule: NotificationSuppressionRule
    ) -> Bool {
        switch category {
        case .incomingMessageFromNoLongerVerifiedIdentity,
             .missedCallWithActions,
             .missedCallWithoutActions,
             .missedCallFromNoLongerVerifiedIdentity,
             .transferRelaunch,
             .deregistration,
             .newDeviceLinked:
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
            // Don't show these notifications when the thread is visible.
            if
                let notificationThreadUniqueId = userInfo[AppNotificationUserInfoKey.threadId] as? String,
                case .messagesInThread(let suppressedThreadUniqueId) = notificationSuppressionRule,
                suppressedThreadUniqueId == notificationThreadUniqueId
            {
                return false
            }
            return true

        case .incomingGroupStoryReply:
            // Show notifications any time we're not currently showing the group reply sheet for that story
            if
                let notificationThreadUniqueId = userInfo[AppNotificationUserInfoKey.threadId] as? String,
                let notificationStoryTimestamp = userInfo[AppNotificationUserInfoKey.storyTimestamp] as? UInt64,
                case .groupStoryReplies(let suppressedThreadUniqueId, let suppressedStoryTimestamp) = notificationSuppressionRule,
                suppressedThreadUniqueId == notificationThreadUniqueId,
                suppressedStoryTimestamp == notificationStoryTimestamp
            {
                return false
            }
            return true

        case .failedStorySend:
            if case .failedStorySends = notificationSuppressionRule {
                return false
            }
            return true
        }
    }

    // MARK: - Replacement

    func replaceNotification(messageId: String) async -> Bool {
        return self.cancelSync(
            notificationRequests: await getNotificationsRequests(),
            matching: .messageIds([messageId])
        )
    }

    // MARK: - Cancellation

    func cancelNotifications(threadId: String) async {
        await cancel(cancellation: .threadId(threadId))
    }

    func cancelNotifications(messageIds: [String]) async {
        await cancel(cancellation: .messageIds(Set(messageIds)))
    }

    func cancelNotifications(reactionId: String) async {
        await cancel(cancellation: .reactionId(reactionId))
    }

    func cancelNotificationsForMissedCalls(withThreadUniqueId threadId: String) async {
        await cancel(cancellation: .missedCalls(inThreadWithUniqueId: threadId))
    }

    func cancelNotificationsForStoryMessage(withUniqueId storyMessageUniqueId: String) async {
        await cancel(cancellation: .storyMessage(storyMessageUniqueId))
    }

    func clearAllNotifications() {
        Logger.info("Clearing all notifications")

        Self.notificationCenter.removeAllPendingNotificationRequests()
        Self.notificationCenter.removeAllDeliveredNotifications()
    }

    static func clearAllNotificationsExceptNewLinkedDevices() {
        Logger.info("Clearing all notifications except new linked device notifications")

        Task {
            let pendingNotificationIDs = await Self.notificationCenter.pendingNotificationRequests()
                .filter { notificationRequest in
                    notificationRequest.content.categoryIdentifier != AppNotificationCategory.newDeviceLinked.identifier
                }
                .map(\.identifier)
            let deliveredNotificationIDs = await Self.notificationCenter.deliveredNotifications()
                .filter { notification in
                    notification.request.content.categoryIdentifier != AppNotificationCategory.newDeviceLinked.identifier
                }
                .map(\.request.identifier)

            Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingNotificationIDs)
            Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: deliveredNotificationIDs)
        }
    }

    private enum CancellationType: Equatable, Hashable {
        case threadId(String)
        case messageIds(Set<String>)
        case reactionId(String)
        case missedCalls(inThreadWithUniqueId: String)
        case storyMessage(String)
    }

    private func getNotificationsRequests() async -> [UNNotificationRequest] {
        return await (
            Self.notificationCenter.deliveredNotifications().map({ $0.request })
            + Self.notificationCenter.pendingNotificationRequests()
        )
    }

    private func cancel(cancellation: CancellationType) async {
        self.cancelSync(notificationRequests: await getNotificationsRequests(), matching: cancellation)
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
