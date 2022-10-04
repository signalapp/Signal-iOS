// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
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

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

protocol NotificationPresenterAdaptee: AnyObject {

    func registerNotificationSettings() -> Promise<Void>

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
    )

    func cancelNotifications(threadId: String)
    func cancelNotifications(identifiers: [String])
    func clearAllNotifications()
}

extension NotificationPresenterAdaptee {
    func notify(
        category: AppNotificationCategory,
        title: String?,
        body: String,
        userInfo: [AnyHashable: Any],
        previewType: Preferences.NotificationPreviewType,
        sound: Preferences.Sound?,
        threadVariant: SessionThread.Variant,
        threadName: String
    ) {
        notify(
            category: category,
            title: title,
            body: body,
            userInfo: userInfo,
            previewType: previewType,
            sound: sound,
            threadVariant: threadVariant,
            threadName: threadName,
            replacingIdentifier: nil
        )
    }
}

@objc(OWSNotificationPresenter)
public class NotificationPresenter: NSObject, NotificationsProtocol {

    private let adaptee: NotificationPresenterAdaptee

    @objc
    public override init() {
        self.adaptee = UserNotificationPresenterAdaptee()

        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Presenting Notifications

    func registerNotificationSettings() -> Promise<Void> {
        return adaptee.registerNotificationSettings()
    }

    public func notifyUser(_ db: Database, for interaction: Interaction, in thread: SessionThread) {
        let isMessageRequest: Bool = thread.isMessageRequest(db, includeNonVisible: true)
        
        // Ensure we should be showing a notification for the thread
        guard thread.shouldShowNotification(db, for: interaction, isMessageRequest: isMessageRequest) else {
            return
        }
        
        // Try to group notifications for interactions from open groups
        let identifier: String = interaction.notificationIdentifier(
            shouldGroupMessagesForThread: (thread.variant == .openGroup)
        )

        // While batch processing, some of the necessary changes have not been commited.
        let rawMessageText = interaction.previewText(db)

        // iOS strips anything that looks like a printf formatting character from
        // the notification body, so if we want to dispay a literal "%" in a notification
        // it must be escaped.
        // see https://developer.apple.com/documentation/uikit/uilocalnotification/1616646-alertbody
        // for more details.
        let messageText: String? = String.filterNotificationText(rawMessageText)
        let notificationTitle: String?
        var notificationBody: String?
        
        let senderName = Profile.displayName(db, id: interaction.authorId, threadVariant: thread.variant)
        let previewType: Preferences.NotificationPreviewType = db[.preferencesNotificationPreviewType]
            .defaulting(to: .defaultPreviewType)
        let groupName: String = SessionThread.displayName(
            threadId: thread.id,
            variant: thread.variant,
            closedGroupName: try? thread.closedGroup
                .select(.name)
                .asRequest(of: String.self)
                .fetchOne(db),
            openGroupName: try? thread.openGroup
                .select(.name)
                .asRequest(of: String.self)
                .fetchOne(db)
        )
        
        switch previewType {
            case .noNameNoPreview:
                notificationTitle = "Session"
                
            case .nameNoPreview, .nameAndPreview:
                switch thread.variant {
                    case .contact:
                        notificationTitle = (isMessageRequest ? "Session" : senderName)
                        
                    case .closedGroup, .openGroup:
                        notificationTitle = String(
                            format: NotificationStrings.incomingGroupMessageTitleFormat,
                            senderName,
                            groupName
                        )
                }
        }
        
        switch previewType {
            case .noNameNoPreview, .nameNoPreview: notificationBody = NotificationStrings.incomingMessageBody
            case .nameAndPreview: notificationBody = messageText
        }
        
        // If it's a message request then overwrite the body to be something generic (only show a notification
        // when receiving a new message request if there aren't any others or the user had hidden them)
        if isMessageRequest {
            notificationBody = "MESSAGE_REQUESTS_NOTIFICATION".localized()
        }

        guard notificationBody != nil || notificationTitle != nil else {
            SNLog("AppNotifications error: No notification content")
            return
        }

        // Don't reply from lockscreen if anyone in this conversation is
        // "no longer verified".
        let category = AppNotificationCategory.incomingMessage

        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.id
        ]
        
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        let userBlindedKey: String? = SessionThread.getUserHexEncodedBlindedKey(
            threadId: thread.id,
            threadVariant: thread.variant
        )
        let fallbackSound: Preferences.Sound = db[.defaultNotificationSound]
            .defaulting(to: Preferences.Sound.defaultNotificationSound)

        DispatchQueue.main.async {
            let sound: Preferences.Sound? = self.requestSound(
                thread: thread,
                fallbackSound: fallbackSound
            )
            
            notificationBody = MentionUtilities.highlightMentionsNoAttributes(
                in: (notificationBody ?? ""),
                threadVariant: thread.variant,
                currentUserPublicKey: userPublicKey,
                currentUserBlindedPublicKey: userBlindedKey
            )
            
            self.adaptee.notify(
                category: category,
                title: notificationTitle,
                body: (notificationBody ?? ""),
                userInfo: userInfo,
                previewType: previewType,
                sound: sound,
                threadVariant: thread.variant,
                threadName: groupName,
                replacingIdentifier: identifier
            )
        }
    }
    
    public func notifyUser(_ db: Database, forIncomingCall interaction: Interaction, in thread: SessionThread) {
        // No call notifications for muted or group threads
        guard Date().timeIntervalSince1970 > (thread.mutedUntilTimestamp ?? 0) else { return }
        guard thread.variant != .closedGroup && thread.variant != .openGroup else { return }
        guard
            interaction.variant == .infoCall,
            let infoMessageData: Data = (interaction.body ?? "").data(using: .utf8),
            let messageInfo: CallMessage.MessageInfo = try? JSONDecoder().decode(
                CallMessage.MessageInfo.self,
                from: infoMessageData
            )
        else { return }
        
        // Only notify missed calls
        guard messageInfo.state == .missed || messageInfo.state == .permissionDenied else { return }
        
        let category = AppNotificationCategory.errorMessage
        let previewType: Preferences.NotificationPreviewType = db[.preferencesNotificationPreviewType]
            .defaulting(to: .nameAndPreview)
        
        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.id
        ]
        
        let notificationTitle: String = "Session"
        let senderName: String = Profile.displayName(db, id: interaction.authorId, threadVariant: thread.variant)
        let notificationBody: String? = {
            switch messageInfo.state {
                case .permissionDenied:
                    return String(
                        format: "modal_call_missed_tips_explanation".localized(),
                        senderName
                    )
                case .missed:
                    return String(
                        format: "call_missed".localized(),
                        senderName
                    )
                default:
                    return nil
            }
        }()
        
        let fallbackSound: Preferences.Sound = db[.defaultNotificationSound]
            .defaulting(to: Preferences.Sound.defaultNotificationSound)
        
        DispatchQueue.main.async {
            let sound = self.requestSound(
                thread: thread,
                fallbackSound: fallbackSound
            )
            
            self.adaptee.notify(
                category: category,
                title: notificationTitle,
                body: (notificationBody ?? ""),
                userInfo: userInfo,
                previewType: previewType,
                sound: sound,
                threadVariant: thread.variant,
                threadName: senderName,
                replacingIdentifier: UUID().uuidString
            )
        }
    }
    
    public func notifyUser(_ db: Database, forReaction reaction: Reaction, in thread: SessionThread) {
        let isMessageRequest: Bool = thread.isMessageRequest(db, includeNonVisible: true)
        
        // No reaction notifications for muted, group threads or message requests
        guard Date().timeIntervalSince1970 > (thread.mutedUntilTimestamp ?? 0) else { return }
        guard thread.variant != .closedGroup && thread.variant != .openGroup else { return }
        guard !isMessageRequest else { return }
        
        let senderName: String = Profile.displayName(db, id: reaction.authorId, threadVariant: thread.variant)
        let notificationTitle = "Session"
        var notificationBody = String(format: "EMOJI_REACTS_NOTIFICATION".localized(), senderName, reaction.emoji)
        
        // Title & body
        let previewType: Preferences.NotificationPreviewType = db[.preferencesNotificationPreviewType]
            .defaulting(to: .nameAndPreview)
        
        switch previewType {
            case .nameAndPreview: break
            default: notificationBody = NotificationStrings.incomingMessageBody
        }
        
        let category = AppNotificationCategory.incomingMessage

        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.id
        ]
        
        let threadName: String = SessionThread.displayName(
            threadId: thread.id,
            variant: thread.variant,
            closedGroupName: nil,       // Not supported
            openGroupName: nil          // Not supported
        )
        let fallbackSound: Preferences.Sound = db[.defaultNotificationSound]
            .defaulting(to: Preferences.Sound.defaultNotificationSound)

        DispatchQueue.main.async {
            let sound = self.requestSound(
                thread: thread,
                fallbackSound: fallbackSound
            )
            
            self.adaptee.notify(
                category: category,
                title: notificationTitle,
                body: notificationBody,
                userInfo: userInfo,
                previewType: previewType,
                sound: sound,
                threadVariant: thread.variant,
                threadName: threadName,
                replacingIdentifier: UUID().uuidString
            )
        }
    }

    public func notifyForFailedSend(_ db: Database, in thread: SessionThread) {
        let notificationTitle: String?
        let previewType: Preferences.NotificationPreviewType = db[.preferencesNotificationPreviewType]
            .defaulting(to: .defaultPreviewType)
        let threadName: String = SessionThread.displayName(
            threadId: thread.id,
            variant: thread.variant,
            closedGroupName: try? thread.closedGroup
                .select(.name)
                .asRequest(of: String.self)
                .fetchOne(db),
            openGroupName: try? thread.openGroup
                .select(.name)
                .asRequest(of: String.self)
                .fetchOne(db),
            isNoteToSelf: (thread.isNoteToSelf(db) == true),
            profile: try? Profile.fetchOne(db, id: thread.id)
        )
        
        switch previewType {
            case .noNameNoPreview: notificationTitle = nil
            case .nameNoPreview, .nameAndPreview: notificationTitle = threadName
        }

        let notificationBody = NotificationStrings.failedToSendBody

        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.id
        ]
        let fallbackSound: Preferences.Sound = db[.defaultNotificationSound]
            .defaulting(to: Preferences.Sound.defaultNotificationSound)

        DispatchQueue.main.async {
            let sound: Preferences.Sound? = self.requestSound(
                thread: thread,
                fallbackSound: fallbackSound
            )
            
            self.adaptee.notify(
                category: .errorMessage,
                title: notificationTitle,
                body: notificationBody,
                userInfo: userInfo,
                previewType: previewType,
                sound: sound,
                threadVariant: thread.variant,
                threadName: threadName
            )
        }
    }
    
    @objc
    public func cancelNotifications(identifiers: [String]) {
        DispatchQueue.main.async {
            self.adaptee.cancelNotifications(identifiers: identifiers)
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

    private func requestSound(thread: SessionThread, fallbackSound: Preferences.Sound) -> Preferences.Sound? {
        guard checkIfShouldPlaySound() else {
            return nil
        }
        
        return (thread.notificationSound ?? fallbackSound)
    }

    private func checkIfShouldPlaySound() -> Bool {
        AssertIsOnMainThread()

        guard UIApplication.shared.applicationState == .active else { return true }
        guard Storage.shared[.playNotificationSoundInForeground] else { return false }

        let nowMs: UInt64 = UInt64(floor(Date().timeIntervalSince1970 * 1000))
        let recentThreshold = nowMs - UInt64(kAudioNotificationsThrottleInterval * Double(kSecondInMs))

        let recentNotifications = mostRecentNotifications.filter { $0 > recentThreshold }

        guard recentNotifications.count < kAudioNotificationsThrottleCount else {
            return false
        }

        mostRecentNotifications.append(nowMs)
        return true
    }
}

class NotificationActionHandler {

    static let shared: NotificationActionHandler = NotificationActionHandler()

    // MARK: - Dependencies

    var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    // MARK: -

    func markAsRead(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId: String = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread: SessionThread = Storage.shared.read({ db in try SessionThread.fetchOne(db, id: threadId) }) else {
            throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
        }

        return markAsRead(thread: thread)
    }

    func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread: SessionThread = Storage.shared.read({ db in try SessionThread.fetchOne(db, id: threadId) }) else {
            throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
        }
        
        let (promise, seal) = Promise<Void>.pending()
        
        Storage.shared.writeAsync { db in
            let interaction: Interaction = try Interaction(
                threadId: thread.id,
                authorId: getUserHexEncodedPublicKey(db),
                variant: .standardOutgoing,
                body: replyText,
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000)),
                hasMention: Interaction.isUserMentioned(db, threadId: threadId, body: replyText),
                expiresInSeconds: try? DisappearingMessagesConfiguration
                    .select(.durationSeconds)
                    .filter(id: threadId)
                    .filter(DisappearingMessagesConfiguration.Columns.isEnabled == true)
                    .asRequest(of: TimeInterval.self)
                    .fetchOne(db)
            ).inserted(db)
            
            try Interaction.markAsRead(
                db,
                interactionId: interaction.id,
                threadId: thread.id,
                includingOlder: true,
                trySendReadReceipt: true
            )
            
            return try MessageSender.sendNonDurably(
                db,
                interaction: interaction,
                in: thread
            )
        }
        .done { seal.fulfill(()) }
        .catch { error in
            Storage.shared.read { [weak self] db in
                self?.notificationPresenter.notifyForFailedSend(db, in: thread)
            }
            
            seal.reject(error)
        }
        .retainUntilComplete()
        
        return promise
    }

    func showThread(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            return showHomeVC()
        }

        // If this happens when the the app is not, visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        let shouldAnimate: Bool = (UIApplication.shared.applicationState == .active)
        SessionApp.presentConversation(for: threadId, animated: shouldAnimate)
        return Promise.value(())
    }
    
    func showHomeVC() -> Promise<Void> {
        SessionApp.showHomeView()
        return Promise.value(())
    }

    private func markAsRead(thread: SessionThread) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        
        Storage.shared.writeAsync(
            updates: { db in
                try Interaction.markAsRead(
                    db,
                    interactionId: try thread.interactions
                        .select(.id)
                        .order(Interaction.Columns.timestampMs.desc)
                        .asRequest(of: Int64?.self)
                        .fetchOne(db),
                    threadId: thread.id,
                    includingOlder: true,
                    trySendReadReceipt: true
                )
            },
            completion: { _, result in
                switch result {
                    case .success: seal.fulfill(())
                    case .failure(let error): seal.reject(error)
                }
            }
        )
        
        return promise
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
