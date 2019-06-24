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
    case infoOrErrorMessage
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
        case .infoOrErrorMessage:
            return "Signal.AppNotificationCategory.infoOrErrorMessage"
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
        case .infoOrErrorMessage:
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

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

protocol NotificationPresenterAdaptee: class {

    func registerNotificationSettings() -> Promise<Void>

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?)

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?, replacingIdentifier: String?)

    func cancelNotifications(threadId: String)
    func clearAllNotifications()

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

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var identityManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    var previewType: NotificationType {
        return preferences.notificationPreviewType()
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

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = callerName
            threadIdentifier = thread.uniqueId
        }
        let notificationBody = NotificationStrings.incomingCallBody

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.localCallId: call.localId.uuidString
        ]

        DispatchQueue.main.async {
            self.adaptee.notify(category: .incomingCall,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                sound: .defaultiOSIncomingRingtone,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    func presentMissedCall(_ call: SignalCall, callerName: String) {

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = callerName
            threadIdentifier = thread.uniqueId
        }
        let notificationBody = NotificationStrings.missedCallBody

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.callBackNumber: remotePhoneNumber
        ]

        DispatchQueue.main.async {
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .missedCall,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    public func presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: SignalCall, callerName: String) {

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = callerName
            threadIdentifier = thread.uniqueId
        }
        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        DispatchQueue.main.async {
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .missedCallFromNoLongerVerifiedIdentity,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    public func presentMissedCallBecauseOfNewIdentity(call: SignalCall, callerName: String) {

        let remotePhoneNumber = call.remotePhoneNumber
        let thread = TSContactThread.getOrCreateThread(contactId: remotePhoneNumber)

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = callerName
            threadIdentifier = thread.uniqueId
        }
        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.callBackNumber: remotePhoneNumber
        ]

        DispatchQueue.main.async {
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .missedCall,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString)
        }
    }

    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, transaction: SDSAnyReadTransaction) {

        guard !thread.isMuted else {
            return
        }

        // While batch processing, some of the necessary changes have not been commited.
        let rawMessageText = incomingMessage.previewText(with: transaction)

        let messageText = rawMessageText.filterStringForDisplay()

        let senderName = contactsManager.displayName(for: incomingMessage.authorId.transitional_signalServiceAddress)

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            switch thread {
            case is TSContactThread:
                notificationTitle = senderName
            case is TSGroupThread:
                var groupName = thread.name()
                if groupName.count < 1 {
                    groupName = MessageStrings.newGroupDefaultTitle
                }
                notificationTitle = String(format: NotificationStrings.incomingGroupMessageTitleFormat,
                                           senderName,
                                           groupName)
            default:
                owsFailDebug("unexpected thread: \(thread)")
                return
            }

            threadIdentifier = thread.uniqueId
        }

        let notificationBody: String?
        if incomingMessage.hasPerMessageExpiration {
            // Don't reveal the contents of messages with per-message expiration.
            notificationBody = NotificationStrings.incomingMessageBody
        } else {
            switch previewType {
            case .noNameNoPreview, .nameNoPreview:
                notificationBody = NotificationStrings.incomingMessageBody
            case .namePreview:
                notificationBody = messageText
            }
        }

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        assert((notificationBody ?? notificationTitle) != nil)

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
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: category,
                                title: notificationTitle,
                                body: notificationBody ?? "",
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                sound: sound)
        }
    }

    public func notifyForFailedSend(inThread thread: TSThread) {
        let notificationTitle: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = thread.name()
        }

        let notificationBody = NotificationStrings.failedToSendBody

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        DispatchQueue.main.async {
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .infoOrErrorMessage,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: nil, // show ungrouped
                                userInfo: userInfo,
                                sound: sound)
        }
    }

    public func notifyUser(for errorMessage: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        notifyUser(for: errorMessage as TSMessage, thread: thread, wantsSound: true, transaction: transaction)
    }

    public func notifyUser(for infoMessage: TSInfoMessage, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction) {
        notifyUser(for: infoMessage as TSMessage, thread: thread, wantsSound: wantsSound, transaction: transaction)
    }

    private func notifyUser(for infoOrErrorMessage: TSMessage, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction) {

        let notificationTitle: String?
        let threadIdentifier: String?
        switch self.previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .namePreview, .nameNoPreview:
            notificationTitle = thread.name()
            threadIdentifier = thread.uniqueId
        }

        let notificationBody = infoOrErrorMessage.previewText(with: transaction)

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        transaction.addCompletion {
            let sound = wantsSound ? self.requestSound(thread: thread) : nil
            self.adaptee.notify(category: .infoOrErrorMessage,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                sound: sound)
        }
    }

    public func notifyUser(forThreadlessErrorMessage errorMessage: TSErrorMessage, transaction: SDSAnyWriteTransaction) {
        let notificationBody = errorMessage.previewText(with: transaction)

        transaction.addCompletion {
            let sound = self.checkIfShouldPlaySound() ? OWSSounds.globalNotificationSound() : nil
            self.adaptee.notify(category: .threadlessErrorMessage,
                                title: nil,
                                body: notificationBody,
                                threadIdentifier: nil,
                                userInfo: [:],
                                sound: sound)
        }
    }

    @objc
    public func cancelNotifications(threadId: String) {
        self.adaptee.cancelNotifications(threadId: threadId)
    }

    @objc
    public func clearAllNotifications() {
        adaptee.clearAllNotifications()
    }

    // MARK: -

    var mostRecentNotifications = TruncatedList<UInt64>(maxLength: kAudioNotificationsThrottleCount)

    private func requestSound(thread: TSThread) -> OWSSound? {
        guard checkIfShouldPlaySound() else {
            return nil
        }

        return OWSSounds.notificationSound(for: thread)
    }

    private func checkIfShouldPlaySound() -> Bool {
        AssertIsOnMainThread()

        guard UIApplication.shared.applicationState == .active else {
            return true
        }

        guard preferences.soundInForeground() else {
            return false
        }

        let now = NSDate.ows_millisecondTimeStamp()
        let recentThreshold = now - UInt64(kAudioNotificationsThrottleInterval * Double(kSecondInMs))

        let recentNotifications = mostRecentNotifications.filter { $0 > recentThreshold }

        guard recentNotifications.count < kAudioNotificationsThrottleCount else {
            return false
        }

        mostRecentNotifications.append(now)
        return true
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

        return markAsRead(thread: thread)
    }

    func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread = TSThread.fetch(uniqueId: threadId) else {
            throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
        }

        return markAsRead(thread: thread).then { () -> Promise<Void> in
            let sendPromise = ThreadUtil.sendMessageNonDurably(text: replyText,
                                                               thread: thread,
                                                               quotedReplyModel: nil,
                                                               messageSender: self.messageSender)

            return sendPromise.recover { error in
                Logger.warn("Failed to send reply message from notification with error: \(error)")
                self.notificationPresenter.notifyForFailedSend(inThread: thread)
            }
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
        signalApp.presentConversationAndScrollToFirstUnreadMessage(forThreadId: threadId, animated: shouldAnimate)
        return Promise.value(())
    }

    private func markAsRead(thread: TSThread) -> Promise<Void> {
        return dbConnection.readWritePromise { transaction in
            thread.markAllAsRead(with: transaction)
        }
    }
}

extension ThreadUtil {
    static var dbReadConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadConnection
    }

    class func sendMessageNonDurably(text: String, thread: TSThread, quotedReplyModel: OWSQuotedReplyModel?, messageSender: MessageSender) -> Promise<Void> {
        return Promise { resolver in
            self.dbReadConnection.read { transaction in
                _ = self.sendMessageNonDurably(withText: text,
                                               in: thread,
                                               quotedReplyModel: quotedReplyModel,
                                               transaction: transaction,
                                               messageSender: messageSender,
                                               completion: resolver.resolve)
            }
        }
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

struct TruncatedList<Element> {
    let maxLength: Int
    private var contents: [Element] = []

    init(maxLength: Int) {
        self.maxLength = maxLength
    }

    mutating func append(_ newElement: Element) {
        var newElements = self.contents
        newElements.append(newElement)
        self.contents = Array(newElements.suffix(maxLength))
    }
}

extension TruncatedList: Collection {
    typealias Index = Int

    var startIndex: Index {
        return contents.startIndex
    }

    var endIndex: Index {
        return contents.endIndex
    }

    subscript (position: Index) -> Element {
        return contents[position]
    }

    func index(after i: Index) -> Index {
        return contents.index(after: i)
    }
}
