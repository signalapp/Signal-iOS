//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

class UserNotificationPresenterAdaptee: NSObject, NotificationPresenterAdaptee {

    private static var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    override init() {
        super.init()
        SwiftSingletons.register(self)
    }

    func registerNotificationSettings() -> Promise<Void> {
        return Promise { future in
            Self.notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
                Self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)

                if granted {
                    Logger.debug("succeeded.")
                } else if let error = error {
                    Logger.error("failed with error: \(error)")
                } else {
                    Logger.info("failed without error. User denied notification permissions.")
                }

                // Note that the promise is fulfilled regardless of if notification permissions were
                // granted. This promise only indicates that the user has responded, so we can
                // proceed with requesting push tokens and complete registration.
                future.resolve()
            }
        }
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], interaction: INInteraction?, sound: OWSSound?,
                completion: NotificationCompletion?) {
        assertOnQueue(NotificationPresenter.notificationQueue)

        notify(category: category, title: title, body: body, threadIdentifier: threadIdentifier, userInfo: userInfo, interaction: interaction, sound: sound, replacingIdentifier: nil, completion: completion)
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], interaction: INInteraction?, sound: OWSSound?, replacingIdentifier: String?,
                completion: NotificationCompletion?) {
        assertOnQueue(NotificationPresenter.notificationQueue)

        guard tsAccountManager.isOnboarded() else {
            Logger.info("suppressing notification since user hasn't yet completed onboarding.")
            completion?()
            return
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        let isAppActive = CurrentAppContext().isMainAppAndActive
        if let sound = sound, sound != OWSStandardSound.none.rawValue {
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
            if let displayableBody = body.filterForDisplay {
                content.body = displayableBody
            }
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

        Logger.info("presenting notification with identifier: \(notificationIdentifier)")
        Self.notificationCenter.add(request) { (error: Error?) in
            if let error = error {
                owsFailDebug("Error: \(error)")
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
        if DebugFlags.internalLogging {
            Logger.info("Presenting notification with identifier: \(notificationIdentifier)")
        }
        let (promise, future) = Promise<Void>.pending()
        Self.notificationCenter.add(request) { (error: Error?) in
            if let error = error {
                owsFailDebug("Error: \(error)")
            }
            future.resolve(())
        }
        return promise
    }

    // MARK: - Cancellation

    public static let cancelQueue = DispatchQueue(label: "org.signal.notifications.cancelQueue")

    private enum PendingCancellation: Equatable, Hashable {
        case threadId(String)
        case messageId(String)
        case reactionId(String)
    }

    private let pendingCancellations = AtomicSet<PendingCancellation>()
    private let isDrainCancellationInFlight = AtomicBool(false)

    // This method is thread-safe.
    private func enqueue(pendingCancellation: PendingCancellation) {
        pendingCancellations.insert(pendingCancellation)
        Self.cancelQueue.async {
            self.drainCancellations()
        }
    }

    private func drainCancellations() {
        assertOnQueue(Self.cancelQueue)

        guard !pendingCancellations.isEmpty else {
            return
        }
        guard isDrainCancellationInFlight.tryToSetFlag() else {
            return
        }

        firstly {
            self.getNotificationRequests()
        }.map(on: Self.cancelQueue) { notificationRequests in
            self.drainCancellations(notificationRequests: notificationRequests)
        }.ensure(on: Self.cancelQueue) {
            self.isDrainCancellationInFlight.set(false)
            self.drainCancellations()
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func getNotificationRequests() -> Promise<[UNNotificationRequest]> {
        assertOnQueue(Self.cancelQueue)

        return firstly {
            Guarantee { resolve in
                Self.notificationCenter.getDeliveredNotifications { resolve($0) }
            }
        }.then(on: Self.cancelQueue) { delivered in
            firstly {
                Guarantee { resolve in
                    Self.notificationCenter.getPendingNotificationRequests { resolve($0) }
                }
            }.map(on: Self.cancelQueue) { pending in
                pending + delivered.map { $0.request }
            }
        }
    }

    private func drainCancellations(notificationRequests: [UNNotificationRequest]) {
        assertOnQueue(Self.cancelQueue)

        let cancellations = pendingCancellations.removeAllValues()
        guard !cancellations.isEmpty else {
            return
        }

        var cancelledThreadIds = Set<String>()
        var cancelledMessageIds = Set<String>()
        var cancelledReactionIds = Set<String>()
        for cancellation in cancellations {
            switch cancellation {
            case .threadId(let threadId):
                cancelledThreadIds.insert(threadId)
            case .messageId(let messageId):
                cancelledMessageIds.insert(messageId)
            case .reactionId(let reactionId):
                cancelledReactionIds.insert(reactionId)
            }
        }

        var identifiersToCancel = [String]()
        for request in notificationRequests {
            if let requestThreadId = request.content.userInfo[AppNotificationUserInfoKey.threadId] as? String,
               cancelledThreadIds.contains(requestThreadId) {
                identifiersToCancel.append(request.identifier)
            }
            if let requestMessageId = request.content.userInfo[AppNotificationUserInfoKey.messageId] as? String,
               cancelledMessageIds.contains(requestMessageId) {
                identifiersToCancel.append(request.identifier)
            }
            if let requestReactionId = request.content.userInfo[AppNotificationUserInfoKey.reactionId] as? String,
               cancelledReactionIds.contains(requestReactionId) {
                identifiersToCancel.append(request.identifier)
            }
        }

        // De-duplicate.
        identifiersToCancel = Array(Set(identifiersToCancel))

        guard !identifiersToCancel.isEmpty else {
            return
        }

        Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToCancel)
        Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
    }

    // This method is thread-safe.
    private func cancelNotificationSync(identifier: String) {
        Self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        Self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // This method is thread-safe.
    private func cancelNotification(_ notification: UNNotificationRequest) {
        cancelNotificationSync(identifier: notification.identifier)
    }

    // This method is thread-safe.
    func cancelNotifications(threadId: String) {
        enqueue(pendingCancellation: .threadId(threadId))
    }

    func cancelNotifications(messageId: String) {
        enqueue(pendingCancellation: .messageId(messageId))
    }

    // This method is thread-safe.
    func cancelNotifications(reactionId: String) {
        enqueue(pendingCancellation: .reactionId(reactionId))
    }

    // This method is thread-safe.
    func clearAllNotifications() {
        pendingCancellations.removeAllValues()
        Self.notificationCenter.removeAllPendingNotificationRequests()
        Self.notificationCenter.removeAllDeliveredNotifications()
    }

    private func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        assertOnQueue(NotificationPresenter.notificationQueue)

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
        case .incomingMessageGeneric:
            owsFailDebug(".incomingMessageGeneric should never check shouldPresentNotification().")
            return true
        }
    }
}

public protocol ConversationSplit {
    var visibleThread: TSThread? { get }
}

extension OWSSound {
    func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = OWSSounds.filename(forSound: self, quiet: isQuiet) else {
            owsFailDebug("[Notification Sounds] sound filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        if
            !FileManager.default.fileExists(atPath: (OWSSounds.soundsDirectory() as NSString).appendingPathComponent(filename))
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
