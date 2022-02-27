//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SessionMessagingKit
import SignalUtilitiesKit

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
}

enum AppNotificationAction: CaseIterable {
    case markAsRead
    case reply
    case showThread
}

struct AppNotificationUserInfoKey {
    static let threadId = "Signal.AppNotificationsUserInfoKey.threadId"
    static let callBackNumber = "Signal.AppNotificationsUserInfoKey.callBackNumber"
    static let localCallId = "Signal.AppNotificationsUserInfoKey.localCallId"
    static let threadNotificationCounter = "Session.AppNotificationsUserInfoKey.threadNotificationCounter"
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
        }
    }
}

extension AppNotificationAction {
    var identifier: String {
        switch self {
        case .markAsRead:
            return "Signal.AppNotifications.Action.markAsRead"
        case .reply:
            return "Signal.AppNotifications.Action.reply"
        case .showThread:
            return "Signal.AppNotifications.Action.showThread"
        }
    }
}

// Delay notification of incoming messages when it's a background polling to
// avoid too many notifications fired at the same time
let kNotificationDelayForBackgroumdPoll: TimeInterval = 5

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

protocol NotificationPresenterAdaptee: AnyObject {

    func registerNotificationSettings() -> Promise<Void>

    func notify(category: AppNotificationCategory, title: String?, body: String, userInfo: [AnyHashable: Any], sound: OWSSound?)
    func notify(category: AppNotificationCategory, title: String?, body: String, userInfo: [AnyHashable: Any], sound: OWSSound?, replacingIdentifier: String?)

    func cancelNotifications(threadId: String)
    func cancelNotification(identifier: String)
    func clearAllNotifications()
}

@objc(OWSNotificationPresenter)
public class NotificationPresenter: NSObject, NotificationsProtocol {

    private let adaptee: NotificationPresenterAdaptee

    @objc
    public override init() {
        self.adaptee = UserNotificationPresenterAdaptee()

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

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    var previewType: NotificationType {
        return preferences.notificationPreviewType()
    }

    // MARK: -

    @objc
    func handleMessageRead(notification: Notification) {
        AssertIsOnMainThread()

        switch notification.object {
        case let incomingMessage as TSIncomingMessage:
            Logger.debug("canceled notification for message: \(incomingMessage)")
            if let identifier = incomingMessage.notificationIdentifier {
                cancelNotification(identifier)
            } else {
                cancelNotifications(threadId: incomingMessage.uniqueThreadId)
            }
        default:
            break
        }
    }

    // MARK: - Presenting Notifications

    func registerNotificationSettings() -> Promise<Void> {
        return adaptee.registerNotificationSettings()
    }

    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, transaction: YapDatabaseReadTransaction) {
        guard !thread.isMuted else { return }
        guard let threadId = thread.uniqueId else { return }
        
        // If the thread is a message request and the user hasn't hidden message requests then we need
        // to check if this is the only message request thread (group threads can't be message requests
        // so just ignore those and if the user has hidden message requests then we want to show the
        // notification regardless of how many message requests there are)
        if !thread.isGroupThread() && thread.isMessageRequest() && !CurrentAppContext().appUserDefaults()[.hasHiddenMessageRequests] {
            let dbConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
            dbConnection.objectCacheLimit = 2
            dbConnection.beginLongLivedReadTransaction() // Freeze the connection for use on the main thread (this gives us a stable data source that doesn't change until we tell it to)
            let threads: YapDatabaseViewMappings = YapDatabaseViewMappings(groups: [ TSMessageRequestGroup ], view: TSThreadDatabaseViewExtensionName)
            dbConnection.read { transaction in
                threads.update(with: transaction) // Perform the initial update
            }
            
            let numMessageRequests = threads.numberOfItems(inGroup: TSMessageRequestGroup)
            dbConnection.endLongLivedReadTransaction()
            
            // Allow this to show a notification if there are no message requests (ie. this is the first one)
            guard numMessageRequests == 0 else { return }
        }
        else if thread.isMessageRequest() && CurrentAppContext().appUserDefaults()[.hasHiddenMessageRequests] {
            // If there are other interactions on this thread already then don't show the notification
            if thread.numberOfInteractions() > 1 { return }
            
            CurrentAppContext().appUserDefaults()[.hasHiddenMessageRequests] = false
        }
        
        let identifier: String = incomingMessage.notificationIdentifier ?? UUID().uuidString
        
        let isBackgroudPoll = identifier == threadId

        // While batch processing, some of the necessary changes have not been commited.
        let rawMessageText = incomingMessage.previewText(with: transaction)

        // iOS strips anything that looks like a printf formatting character from
        // the notification body, so if we want to dispay a literal "%" in a notification
        // it must be escaped.
        // see https://developer.apple.com/documentation/uikit/uilocalnotification/1616646-alertbody
        // for more details.
        let messageText = DisplayableText.filterNotificationText(rawMessageText)
        
        // Don't fire the notification if the current user isn't mentioned
        // and isOnlyNotifyingForMentions is on.
        if let groupThread = thread as? TSGroupThread, groupThread.isOnlyNotifyingForMentions && !incomingMessage.isUserMentioned {
            return
        }

        let context = Contact.context(for: thread)
        let senderName = Storage.shared.getContact(with: incomingMessage.authorId, using: transaction)?.displayName(for: context) ?? incomingMessage.authorId

        let notificationTitle: String?
        var notificationBody: String?
        let previewType = preferences.notificationPreviewType(with: transaction)
        
        switch previewType {
            case .noNameNoPreview:
                notificationTitle = "Session"
                
            case .nameNoPreview, .namePreview:
                switch thread {
                    case is TSContactThread:
                        notificationTitle = (thread.isMessageRequest() ? "Session" : senderName)
                        
                    case is TSGroupThread:
                        var groupName = thread.name()
                        if groupName.count < 1 {
                            groupName = MessageStrings.newGroupDefaultTitle
                        }
                        notificationTitle = isBackgroudPoll ? groupName : String(format: NotificationStrings.incomingGroupMessageTitleFormat, senderName, groupName)
                        
                    default:
                        owsFailDebug("unexpected thread: \(thread)")
                        return
                }
                
            default:
                notificationTitle = "Session"
        }
        
        switch previewType {
            case .noNameNoPreview, .nameNoPreview: notificationBody = NotificationStrings.incomingMessageBody
            case .namePreview: notificationBody = messageText
            default: notificationBody = NotificationStrings.incomingMessageBody
        }
        
        // If it's a message request then overwrite the body to be something generic (only show a notification
        // when receiving a new message request if there aren't any others or the user had hidden them)
        if thread.isMessageRequest() {
            notificationBody = NSLocalizedString("MESSAGE_REQUESTS_NOTIFICATION", comment: "")
        }

        assert((notificationBody ?? notificationTitle) != nil)

        // Don't reply from lockscreen if anyone in this conversation is
        // "no longer verified".
        let category = AppNotificationCategory.incomingMessage

        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        DispatchQueue.main.async {
            notificationBody = MentionUtilities.highlightMentions(in: notificationBody!, threadID: thread.uniqueId!)
            let sound = self.requestSound(thread: thread)
            
            self.adaptee.notify(
                category: category,
                title: notificationTitle,
                body: notificationBody ?? "",
                userInfo: userInfo,
                sound: sound,
                replacingIdentifier: identifier
            )
        }
    }

    public func notifyForFailedSend(inThread thread: TSThread) {
        let notificationTitle: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = thread.name()
        default:
            notificationTitle = nil
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
            self.adaptee.notify(category: .errorMessage,
                                title: notificationTitle,
                                body: notificationBody,
                                userInfo: userInfo,
                                sound: sound)
        }
    }
    
    @objc
    public func cancelNotification(_ identifier: String) {
        DispatchQueue.main.async {
            self.adaptee.cancelNotification(identifier: identifier)
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

    var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // MARK: -

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
            let message = VisibleMessage()
            message.sentTimestamp = NSDate.millisecondTimestamp()
            message.text = replyText
            let tsMessage = TSOutgoingMessage.from(message, associatedWith: thread)
            Storage.write { transaction in
                tsMessage.save(with: transaction)
            }
            var promise: Promise<Void>!
            Storage.writeSync { transaction in
                promise = MessageSender.sendNonDurably(message, in: thread, using: transaction)
            }
            promise.catch { [weak self] error in
                self?.notificationPresenter.notifyForFailedSend(inThread: thread)
            }
            return promise
        }
    }

    func showThread(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            return showHomeVC()
        }

        // If this happens when the the app is not, visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        let shouldAnimate = UIApplication.shared.applicationState == .active
        signalApp.presentConversationAndScrollToFirstUnreadMessage(forThreadId: threadId, animated: shouldAnimate)
        return Promise.value(())
    }
    
    func showHomeVC() -> Promise<Void> {
        signalApp.showHomeView()
        return Promise.value(())
    }

    private func markAsRead(thread: TSThread) -> Promise<Void> {
        return Storage.write { transaction in
            thread.markAllAsRead(with: transaction)
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
