//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UserNotifications
import PromiseKit
import Intents

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
        }
    }

    private class func notificationActionWithIdentifier(
        _ identifier: String,
        title: String,
        options: UNNotificationActionOptions,
        systemImage: String?) -> UNNotificationAction {
        #if swift(>=5.5) // TODO Temporary for Xcode 12 support.
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
        #else
            return UNNotificationAction(identifier: identifier,
                                        title: title,
                                        options: options)
        #endif
    }

    private class func textInputNotificationActionWithIdentifier(
        _ identifier: String,
        title: String,
        options: UNNotificationActionOptions,
        textInputButtonTitle: String,
        textInputPlaceholder: String,
        systemImage: String?) -> UNNotificationAction {
        #if swift(>=5.5) // TODO Temporary for Xcode 12 support.
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
        #else
            return UNTextInputNotificationAction(identifier: identifier,
                                                 title: title,
                                                 options: options,
                                                 textInputButtonTitle: textInputButtonTitle,
                                                 textInputPlaceholder: textInputPlaceholder)
        #endif
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

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], interaction: INInteraction?, sound: OWSSound?) {
        AssertIsOnMainThread()
        notify(category: category, title: title, body: body, threadIdentifier: threadIdentifier, userInfo: userInfo, interaction: interaction, sound: sound, replacingIdentifier: nil)
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], interaction: INInteraction?, sound: OWSSound?, replacingIdentifier: String?) {
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

        let contentToUse: UNNotificationContent = content
        let postNotification = {
            let request = UNNotificationRequest(identifier: notificationIdentifier, content: contentToUse, trigger: trigger)

            if DebugFlags.internalLogging {
                Logger.info("presenting notification with identifier: \(notificationIdentifier)")
            }
            if DebugFlags.internalLogging {
                Logger.info("Posting: \(notificationIdentifier).")
            }
            self.notificationCenter.add(request) { (error: Error?) in
                if let error = error {
                    owsFailDebug("Error: \(error)")
                } else if DebugFlags.internalLogging {
                    Logger.info("Posted: \(notificationIdentifier).")
                }
            }
        }
        #if swift(>=5.5) // TODO Temporary for Xcode 12 support.
        if #available(iOS 15, *), let interaction = interaction {
            if DebugFlags.internalLogging {
                Logger.info("Will donate interaction")
            }

            let group = DispatchGroup()
            group.enter()
            interaction.donate(completion: { error in
                if DebugFlags.internalLogging { Logger.info("Did donate interaction") }

                group.leave()

                if let error = error {
                    owsFailDebug("Failed to donate incoming message intent \(error)")
                    return
                }
            })

            if case .timedOut = group.wait(timeout: .now() + 1.0) {
                Logger.warn("Timed out donating intent")
            }

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

            postNotification()
        }
        #else
        postNotification()
        #endif

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

    private func drainCancelations() {
        AssertIsOnMainThread()

        guard !pendingCancelations.isEmpty else { return }

        let requests = getNotificationRequests().wait()

        var identifiersToCancel = [String]()

        requestLoop:
        for request in requests {
            for cancelation in self.pendingCancelations {
                switch cancelation {
                case .threadId(let threadId):
                    let requestThreadId = request.content.userInfo[AppNotificationUserInfoKey.threadId] as? String
                    if threadId == requestThreadId {
                        identifiersToCancel.append(request.identifier)
                        pendingCancelations.remove(cancelation)
                        continue requestLoop
                    }
                case .messageId(let messageId):
                    let requestMessageId = request.content.userInfo[AppNotificationUserInfoKey.messageId] as? String
                    if messageId == requestMessageId {
                        identifiersToCancel.append(request.identifier)
                        pendingCancelations.remove(cancelation)
                        continue requestLoop
                    }
                case .reactionId(let reactionId):
                    let requestReactionId = request.content.userInfo[AppNotificationUserInfoKey.reactionId] as? String
                    if reactionId == requestReactionId {
                        identifiersToCancel.append(request.identifier)
                        pendingCancelations.remove(cancelation)
                        continue requestLoop
                    }
                }
            }
        }

        if DebugFlags.internalLogging {
            Logger.info("identifiersToCancel: \(identifiersToCancel)")
        }

        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToCancel)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)

        // Remove anything lingering that didn't match a request,
        // we've checked all the requests.
        pendingCancelations.removeAll()
    }

    func cancelNotification(identifier: String) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("cancelNotification: \(identifier)")
        }

        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotification(_ notification: UNNotificationRequest) {
        AssertIsOnMainThread()

        cancelNotification(identifier: notification.identifier)
    }

    func cancelNotifications(threadId: String) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("threadId: \(threadId)")
        }

        pendingCancelations.insert(.threadId(threadId))
    }

    func cancelNotifications(messageId: String) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("messageId: \(messageId)")
        }

        pendingCancelations.insert(.messageId(messageId))
    }

    func cancelNotifications(reactionId: String) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("reactionId: \(reactionId)")
        }

        pendingCancelations.insert(.reactionId(reactionId))
    }

    func clearAllNotifications() {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("")
        }

        pendingCancelations.removeAll()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        AssertIsOnMainThread()
        switch category {
        case .incomingMessageFromNoLongerVerifiedIdentity,
             .threadlessErrorMessage,
             .incomingCall,
             .missedCallWithActions,
             .missedCallWithoutActions,
             .missedCallFromNoLongerVerifiedIdentity:
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
        }
    }

    func getNotificationRequests() -> Guarantee<[UNNotificationRequest]> {
        return getDeliveredNotifications().then(on: .global()) { delivered in
            self.getPendingNotificationRequests().map(on: .global()) { pending in
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
