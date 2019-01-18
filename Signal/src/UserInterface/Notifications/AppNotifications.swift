//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

/// There are two primary components in our system notification integration:
///
///     1. The `NotificationPresenter` shows system notifications to the user.
///     2. The `NotificationActionHandler` handles the users interactions with these
///        notifications.
///
/// The NotificationPresenter is driven by the adapter pattern to provide a unified interface to
/// presenting notifications on iOS9, which uses UINotifications vs iOS10+ which supports
/// UNUserNotifications.
///
/// The `NotificationActionHandler`s also need slightly different integrations for UINotifications
/// vs. UNUserNotifications, but because they are integrated at separate system defined callbacks,
/// there is no need for an Adapter, and instead the appropriate NotificationActionHandler is
/// wired directly into the appropriate callback point.

enum AppNotificationCategory: CaseIterable {
    case incomingMessage
    case incomingMessageFromNoLongerVerifiedIdentity
    case errorMessage
    case threadlessErrorMessage
    case incomingCall
    case missedCall
    case missedCallFromNoLongerVerifiedIdentity
}

enum AppNotificationAction: CaseIterable {
    case answerCall
    case callBack
    case declineCall
    case markAsRead
    case reply
    case showThread
}

struct AppNotificationUserInfoKey {
    static let threadId = "Signal.AppNotificationsUserInfoKey.threadId"
    static let callBackNumber = "Signal.AppNotificationsUserInfoKey.callBackNumber"
    static let localCallId = "Signal.AppNotificationsUserInfoKey.localCallId"
}

extension AppNotificationCategory {
    var identifier: String {
        switch self {
        case .incomingMessage:
            return "Signal.AppNotificationCategory.incomingMessage"
        case .incomingMessageFromNoLongerVerifiedIdentity:
            return "Signal.AppNotificationCategory.incomingMessageFromNoLongerVerifiedIdentity"
        case .errorMessage:
            return "Signal.AppNotificationCategory.errorMessage"
        case .threadlessErrorMessage:
            return "Signal.AppNotificationCategory.threadlessErrorMessage"
        case .incomingCall:
            return "Signal.AppNotificationCategory.incomingCall"
        case .missedCall:
            return "Signal.AppNotificationCategory.missedCall"
        case .missedCallFromNoLongerVerifiedIdentity:
            return "Signal.AppNotificationCategory.missedCallFromNoLongerVerifiedIdentity"
        }
    }

    var actions: [AppNotificationAction] {
        switch self {
        case .incomingMessage:
            return [.markAsRead, .reply]
        case .incomingMessageFromNoLongerVerifiedIdentity:
            return [.markAsRead, .showThread]
        case .errorMessage:
            return [.showThread]
        case .threadlessErrorMessage:
            return []
        case .incomingCall:
            return [.answerCall, .declineCall]
        case .missedCall:
            return [.callBack, .showThread]
        case .missedCallFromNoLongerVerifiedIdentity:
            return [.showThread]
        }
    }
}

extension AppNotificationAction {
    var identifier: String {
        switch self {
        case .answerCall:
            return "Signal.AppNotifications.Action.answerCall"
        case .callBack:
            return "Signal.AppNotifications.Action.callBack"
        case .declineCall:
            return "Signal.AppNotifications.Action.declineCall"
        case .markAsRead:
            return "Signal.AppNotifications.Action.markAsRead"
        case .reply:
            return "Signal.AppNotifications.Action.reply"
        case .showThread:
            return "Signal.AppNotifications.Action.showThread"
        }
    }
}

// Delay notification of incoming messages when it's likely to be read by a linked device to
// avoid notifying a user on their phone while a conversation is actively happening on desktop.
let kNotificationDelayForRemoteRead: TimeInterval = 5

protocol NotificationPresenterAdaptee: class {

    func registerNotificationSettings() -> Promise<Void>

    func notify(category: AppNotificationCategory, body: String, userInfo: [AnyHashable: Any], sound: OWSSound?)
    func notify(category: AppNotificationCategory, body: String, userInfo: [AnyHashable: Any], sound: OWSSound?, replacingIdentifier: String?)

    func cancelNotifications(threadId: String)
    func clearAllNotifications()

    var shouldPlaySoundForNotification: Bool { get }
    var hasReceivedSyncMessageRecently: Bool { get }
}

extension NotificationPresenterAdaptee {
    var hasReceivedSyncMessageRecently: Bool {
        return OWSDeviceManager.shared().hasReceivedSyncMessage(inLastSeconds: 60)
    }
}

@objc(OWSNotificationPresenter)
public class NotificationPresenter: NSObject, NotificationsProtocol {

    private let adaptee: NotificationPresenterAdaptee

    @objc
    public override init() {
        if #available(iOS 10, *) {
            self.adaptee = UserNotificationPresenterAdaptee()
        } else {
            self.adaptee = LegacyNotificationPresenterAdaptee()
        }

        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            NotificationCenter.default.addObserver(self, selector: #selector(self.handleMessageRead), name: .incomingMessageMarkedAsRead, object: nil)
        }
        SwiftSingletons.register(self)
    }

    // MARK: - Dependencies

    var identityManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    var previewType: NotificationType {
        return Environment.shared.preferences.notificationPreviewType()
    }

    // MARK: -

    // It is not safe to assume push token requests will be acknowledged until the user has
    // registered their notification settings.
    //
    // e.g. in the case that Background Fetch is disabled, token requests will be ignored until
    // we register user notification settings.
    //
    // For modern UNUserNotificationSettings, the registration takes a callback, so "waiting" for
    // notification settings registration is straight forward, however for legacy UIUserNotification
    // settings, the settings request is confirmed in the AppDelegate, where we call this method
    // to inform the adaptee it's safe to proceed.
    @objc
    public func didRegisterLegacyNotificationSettings() {
        guard let legacyAdaptee = adaptee as? LegacyNotificationPresenterAdaptee else {
            owsFailDebug("unexpected notifications adaptee: \(adaptee)")
            return
        }
        legacyAdaptee.didRegisterUserNotificationSettings()
    }

    @objc
    func handleMessageRead(notification: Notification) {
        AssertIsOnMainThread()

        switch notification.object {
        case let incomingMessage as TSIncomingMessage:
            Logger.debug("canceled notification for message: \(incomingMessage)")
            cancelNotifications(threadId: incomingMessage.uniqueThreadId)
        default:
            break
        }
    }

    // MARK: - Presenting Notifications

    func registerNotificationSettings() -> Promise<Void> {
        return adaptee.registerNotificationSettings()
    }

    func presentIncomingCall(_ call: SignalCall, callerName: String) {
        let alertMessage: String
        switch previewType {
        case .noNameNoPreview:
            alertMessage = CallStrings.incomingCallWithoutCallerNameNotification
        case .nameNoPreview, .namePreview:
            alertMessage = String(format: CallStrings.incomingCallNotificationFormat, callerName)
        }
        let notificationBody = "☎️".rtlSafeAppend(" ").rtlSafeAppend(alertMessage)

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.localCallId: call.localId.uuidString
        ]

        let sound = OWSSound.defaultiOSIncomingRingtone

        DispatchQueue.main.async {
            self.adaptee.notify(category: .incomingCall,
                                body: notificationBody,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    func presentMissedCall(_ call: SignalCall, callerName: String) {
        let notificationBody: String
        switch previewType {
        case .noNameNoPreview:
            notificationBody = CallStrings.missedCallNotificationBodyWithoutCallerName
        case .nameNoPreview, .namePreview:
            notificationBody = String(format: CallStrings.missedCallNotificationBodyWithCallerName, callerName)
        }

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.notificationSound(for: thread)
        } else {
            sound = nil
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.localCallId: call.localId.uuidString
        ]

        DispatchQueue.main.async {
            self.adaptee.notify(category: .missedCall,
                                body: notificationBody,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    public func presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: SignalCall, callerName: String) {
        let notificationBody: String
        switch previewType {
        case .noNameNoPreview:
            notificationBody = CallStrings.missedCallWithIdentityChangeNotificationBodyWithoutCallerName
        case .nameNoPreview, .namePreview:
            notificationBody = String(format: CallStrings.missedCallWithIdentityChangeNotificationBodyWithCallerName, callerName)
        }

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)
        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.notificationSound(for: thread)
        } else {
            sound = nil
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        DispatchQueue.main.async {
            self.adaptee.notify(category: .missedCallFromNoLongerVerifiedIdentity,
                                body: notificationBody,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    public func presentMissedCallBecauseOfNewIdentity(call: SignalCall, callerName: String) {

        let notificationBody: String
        switch previewType {
        case .noNameNoPreview:
            notificationBody = CallStrings.missedCallWithIdentityChangeNotificationBodyWithoutCallerName
        case .nameNoPreview, .namePreview:
            notificationBody = String(format: CallStrings.missedCallWithIdentityChangeNotificationBodyWithCallerName, callerName)
        }

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.notificationSound(for: thread)
        } else {
            sound = nil
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.callBackNumber: remotePhoneNumber
        ]

        DispatchQueue.main.async {
            self.adaptee.notify(category: .missedCall,
                                body: notificationBody,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    // MJK TODO DI contactsManager
    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, contactsManager: ContactsManagerProtocol, transaction: YapDatabaseReadTransaction) {

        guard !thread.isMuted else {
            return
        }

        // While batch processing, some of the necessary changes have not been commited.
        let rawMessageText = incomingMessage.previewText(with: transaction)

        // iOS strips anything that looks like a printf formatting character from
        // the notification body, so if we want to dispay a literal "%" in a notification
        // it must be escaped.
        // see https://developer.apple.com/documentation/uikit/uilocalnotification/1616646-alertbody
        // for more details.
        let messageText = DisplayableText.filterNotificationText(rawMessageText)

        let senderName = contactsManager.displayName(forPhoneIdentifier: incomingMessage.authorId)

        let notificationBody: String

        switch previewType {
        case .noNameNoPreview:
            notificationBody = NSLocalizedString("APN_Message", comment: "")
        case .nameNoPreview:
            switch thread {
            case is TSContactThread:
                // TODO - should this be a format string? seems weird we're hardcoding in a ":"
                let fromText = NSLocalizedString("APN_MESSAGE_FROM", comment: "")
                notificationBody = String(format: "%@: %@", fromText, senderName)
            case is TSGroupThread:
                var groupName = thread.name()
                if groupName.count < 1 {
                    groupName = MessageStrings.newGroupDefaultTitle
                }
                // TODO - should this be a format string? seems weird we're hardcoding in the quotes
                let fromText = NSLocalizedString("APN_MESSAGE_IN_GROUP", comment: "")
                notificationBody = String(format: "%@ \"%@\"", fromText, groupName)
            default:
                owsFailDebug("unexpected thread: \(thread)")
                return
            }
        case .namePreview:
            switch thread {
            case is TSContactThread:
                notificationBody = String(format: "%@: %@", senderName, messageText ?? "")
            case is TSGroupThread:
                var groupName = thread.name()
                if groupName.count < 1 {
                    groupName = MessageStrings.newGroupDefaultTitle
                }
                let threadName = String(format: "\"%@\"", groupName)

                let bodyFormat = NSLocalizedString("APN_MESSAGE_IN_GROUP_DETAILED", comment: "")
                notificationBody = String(format: bodyFormat, senderName, threadName, messageText ?? "")
            default:
                owsFailDebug("unexpected thread: \(thread)")
                return
            }
        }

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.notificationSound(for: thread)
        } else {
            sound = nil
        }

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        // Don't reply from lockscreen if anyone in this conversation is
        // "no longer verified".
        var category = AppNotificationCategory.incomingMessage
        for recipientId in thread.recipientIdentifiers {
            if self.identityManager.verificationState(forRecipientId: recipientId) == .noLongerVerified {
                category = AppNotificationCategory.incomingMessageFromNoLongerVerifiedIdentity
                break
            }
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        DispatchQueue.main.async {
            self.adaptee.notify(category: category, body: notificationBody, userInfo: userInfo, sound: sound)
        }
    }

    public func notifyForFailedSend(inThread thread: TSThread) {
        let notificationFormat = NSLocalizedString("NOTIFICATION_SEND_FAILED", comment: "subsequent notification body when replying from notification fails")
        let notificationBody = String(format: notificationFormat, thread.name())

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.notificationSound(for: thread)
        } else {
            sound = nil
        }

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        DispatchQueue.main.async {
            self.adaptee.notify(category: .errorMessage, body: notificationBody, userInfo: userInfo, sound: sound)
        }
    }

    public func notifyUser(for errorMessage: TSErrorMessage, thread: TSThread, transaction: YapDatabaseReadWriteTransaction) {
        let messageText = errorMessage.previewText(with: transaction)
        let authorName = thread.name()

        let notificationBody: String
        switch self.previewType {
        case .namePreview, .nameNoPreview:
            // TODO better format string, seems weird to hardcode ":"
            notificationBody = authorName.rtlSafeAppend(":").rtlSafeAppend(" ").rtlSafeAppend(messageText)
        case .noNameNoPreview:
            notificationBody = messageText
        }

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.notificationSound(for: thread)
        } else {
            sound = nil
        }

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        transaction.addCompletionQueue(DispatchQueue.main) {
            self.adaptee.notify(category: .errorMessage, body: notificationBody, userInfo: userInfo, sound: sound)
        }
    }

    public func notifyUser(forThreadlessErrorMessage errorMessage: TSErrorMessage, transaction: YapDatabaseReadWriteTransaction) {
        let notificationBody = errorMessage.previewText(with: transaction)

        let sound: OWSSound?
        if shouldPlaySoundForNotification {
            sound = OWSSounds.globalNotificationSound()
        } else {
            sound = nil
        }

        transaction.addCompletionQueue(DispatchQueue.main) {
            self.adaptee.notify(category: .threadlessErrorMessage, body: notificationBody, userInfo: [:], sound: sound)
        }
    }

    public func cancelNotifications(threadId: String) {
        self.adaptee.cancelNotifications(threadId: threadId)
    }

    public func clearAllNotifications() {
        adaptee.clearAllNotifications()
    }

    // TODO rename to something like 'shouldThrottle' or 'requestAudioUsage'
    var shouldPlaySoundForNotification: Bool {
        return adaptee.shouldPlaySoundForNotification
    }
}

class NotificationActionHandler {

    static let shared: NotificationActionHandler = NotificationActionHandler()

    // MARK: - Dependencies

    var signalApp: SignalApp {
        return SignalApp.shared()
    }

    var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    var callUIAdapter: CallUIAdapter {
        return AppEnvironment.shared.callService.callUIAdapter
    }

    var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // MARK: -

    func answerCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw NotificationError.failDebug("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw NotificationError.failDebug("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        callUIAdapter.answerCall(localId: localCallId)
        return Promise.value(())
    }

    func callBack(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let recipientId = userInfo[AppNotificationUserInfoKey.callBackNumber] as? String else {
            throw NotificationError.failDebug("recipientId was unexpectedly nil")
        }

        callUIAdapter.startAndShowOutgoingCall(recipientId: recipientId, hasLocalVideo: false)
        return Promise.value(())
    }

    func declineCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw NotificationError.failDebug("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw NotificationError.failDebug("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        callUIAdapter.declineCall(localId: localCallId)
        return Promise.value(())
    }

    func markAsRead(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread = TSThread.fetch(uniqueId: threadId) else {
            throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
        }

        return Promise { resolver in
            self.dbConnection.asyncReadWrite({ transaction in
                thread.markAllAsRead(with: transaction)
            },
                                        completionBlock: {
                                            self.notificationPresenter.cancelNotifications(threadId: threadId)
                                            resolver.fulfill(())
            })
        }
    }

    func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread = TSThread.fetch(uniqueId: threadId) else {
            throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
        }

        return ThreadUtil.sendMessageNonDurably(text: replyText,
                                                thread: thread,
                                                quotedReplyModel: nil,
                                                messageSender: messageSender).recover { error in
                                                    Logger.warn("Failed to send reply message from notification with error: \(error)")
                                                    self.notificationPresenter.notifyForFailedSend(inThread: thread)
        }
    }

    func showThread(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        // If this happens when the the app is not, visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        let shouldAnimate = UIApplication.shared.applicationState == .active
        signalApp.presentConversation(forThreadId: threadId, animated: shouldAnimate)
        return Promise.value(())
    }
}

extension ThreadUtil {
    class func sendMessageNonDurably(text: String, thread: TSThread, quotedReplyModel: OWSQuotedReplyModel?, messageSender: MessageSender) -> Promise<Void> {
        return Promise { resolver in
            self.sendMessageNonDurably(withText: text,
                                       in: thread,
                                       quotedReplyModel: quotedReplyModel,
                                       messageSender: messageSender,
                                       success: resolver.fulfill,
                                       failure: resolver.reject)
        }
    }
}

extension OWSSound {
    var filename: String? {
        return OWSSounds.filename(for: self)
    }
}

enum NotificationError: Error {
    case assertionError(description: String)
}

extension NotificationError {
    static func failDebug(_ description: String) -> NotificationError {
        owsFailDebug(description)
        return NotificationError.assertionError(description: description)
    }
}
