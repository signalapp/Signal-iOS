//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import Intents
import SignalServiceKit

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

public enum AppNotificationCategory: CaseIterable {
    case incomingMessageWithActions_CanReply
    case incomingMessageWithActions_CannotReply
    case incomingMessageWithoutActions
    case incomingMessageFromNoLongerVerifiedIdentity
    case incomingReactionWithActions_CanReply
    case incomingReactionWithActions_CannotReply
    case infoOrErrorMessage
    case threadlessErrorMessage
    case incomingCall
    case missedCallWithActions
    case missedCallWithoutActions
    case missedCallFromNoLongerVerifiedIdentity
    case internalError
    case incomingMessageGeneric
}

public enum AppNotificationAction: String, CaseIterable {
    case answerCall
    case callBack
    case declineCall
    case markAsRead
    case reply
    case showThread
    case reactWithThumbsUp
    case showCallLobby
    case submitDebugLogs
}

public struct AppNotificationUserInfoKey {
    public static let threadId = "Signal.AppNotificationsUserInfoKey.threadId"
    public static let messageId = "Signal.AppNotificationsUserInfoKey.messageId"
    public static let reactionId = "Signal.AppNotificationsUserInfoKey.reactionId"
    public static let callBackUuid = "Signal.AppNotificationsUserInfoKey.callBackUuid"
    public static let callBackPhoneNumber = "Signal.AppNotificationsUserInfoKey.callBackPhoneNumber"
    public static let localCallId = "Signal.AppNotificationsUserInfoKey.localCallId"
    public static let defaultAction = "Signal.AppNotificationsUserInfoKey.defaultAction"
}

extension AppNotificationCategory {
    var identifier: String {
        switch self {
        case .incomingMessageWithActions_CanReply:
            return "Signal.AppNotificationCategory.incomingMessageWithActions"
        case .incomingMessageWithActions_CannotReply:
            return "Signal.AppNotificationCategory.incomingMessageWithActionsNoReply"
        case .incomingMessageWithoutActions:
            return "Signal.AppNotificationCategory.incomingMessage"
        case .incomingMessageFromNoLongerVerifiedIdentity:
            return "Signal.AppNotificationCategory.incomingMessageFromNoLongerVerifiedIdentity"
        case .incomingReactionWithActions_CanReply:
            return "Signal.AppNotificationCategory.incomingReactionWithActions"
        case .incomingReactionWithActions_CannotReply:
            return "Signal.AppNotificationCategory.incomingReactionWithActionsNoReply"
        case .infoOrErrorMessage:
            return "Signal.AppNotificationCategory.infoOrErrorMessage"
        case .threadlessErrorMessage:
            return "Signal.AppNotificationCategory.threadlessErrorMessage"
        case .incomingCall:
            return "Signal.AppNotificationCategory.incomingCall"
        case .missedCallWithActions:
            return "Signal.AppNotificationCategory.missedCallWithActions"
        case .missedCallWithoutActions:
            return "Signal.AppNotificationCategory.missedCall"
        case .missedCallFromNoLongerVerifiedIdentity:
            return "Signal.AppNotificationCategory.missedCallFromNoLongerVerifiedIdentity"
        case .internalError:
            return "Signal.AppNotificationCategory.internalError"
        case .incomingMessageGeneric:
            return "Signal.AppNotificationCategory.incomingMessageGeneric"
        }
    }

    var actions: [AppNotificationAction] {
        switch self {
        case .incomingMessageWithActions_CanReply:
            if DebugFlags.reactWithThumbsUpFromLockscreen {
                return [.markAsRead, .reply, .reactWithThumbsUp]
            } else {
                return [.markAsRead, .reply]
            }
        case .incomingMessageWithActions_CannotReply:
            return [.markAsRead]
        case .incomingReactionWithActions_CanReply:
            return [.markAsRead, .reply]
        case .incomingReactionWithActions_CannotReply:
            return [.markAsRead]
        case .incomingMessageWithoutActions,
             .incomingMessageFromNoLongerVerifiedIdentity:
            return []
        case .infoOrErrorMessage:
            return []
        case .threadlessErrorMessage:
            return []
        case .incomingCall:
            return [.answerCall, .declineCall]
        case .missedCallWithActions:
            return [.callBack, .showThread]
        case .missedCallWithoutActions:
            return []
        case .missedCallFromNoLongerVerifiedIdentity:
            return []
        case .internalError:
            return []
        case .incomingMessageGeneric:
            return []
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
        case .reactWithThumbsUp:
            return "Signal.AppNotifications.Action.reactWithThumbsUp"
        case .showCallLobby:
            return "Signal.AppNotifications.Action.showCallLobby"
        case .submitDebugLogs:
            return "Signal.AppNotifications.Action.submitDebugLogs"
        }
    }
}

// Delay notification of incoming messages when it's likely to be read by a linked device to
// avoid notifying a user on their phone while a conversation is actively happening on desktop.
let kNotificationDelayForRemoteRead: TimeInterval = 20

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

typealias NotificationCompletion = () -> Void

protocol NotificationPresenterAdaptee: AnyObject {

    func registerNotificationSettings() -> Promise<Void>

    func notify(category: AppNotificationCategory,
                title: String?,
                body: String,
                threadIdentifier: String?,
                userInfo: [AnyHashable: Any],
                interaction: INInteraction?,
                sound: OWSSound?,
                completion: NotificationCompletion?)

    func notify(category: AppNotificationCategory,
                title: String?,
                body: String,
                threadIdentifier: String?,
                userInfo: [AnyHashable: Any],
                interaction: INInteraction?,
                sound: OWSSound?,
                replacingIdentifier: String?,
                completion: NotificationCompletion?)

    func postGenericIncomingMessageNotification() -> Promise<Void>

    func cancelNotifications(threadId: String)
    func cancelNotifications(messageId: String)
    func cancelNotifications(reactionId: String)
    func clearAllNotifications()

    var hasReceivedSyncMessageRecently: Bool { get }
}

// MARK: -

extension NotificationPresenterAdaptee {
    var hasReceivedSyncMessageRecently: Bool {
        return OWSDeviceManager.shared().hasReceivedSyncMessage(inLastSeconds: 60)
    }
}

// MARK: -

@objc(OWSNotificationPresenter)
public class NotificationPresenter: NSObject, NotificationsProtocol {
    private let adaptee: NotificationPresenterAdaptee

    @objc
    public override init() {
        self.adaptee = UserNotificationPresenterAdaptee()

        super.init()

        SwiftSingletons.register(self)
    }

    var previewType: NotificationType {
        return preferences.notificationPreviewType()
    }

    var shouldShowActions: Bool {
        return previewType == .namePreview
    }

    // MARK: - Presenting Notifications

    public func registerNotificationSettings() -> Promise<Void> {
        return adaptee.registerNotificationSettings()
    }

    public func presentIncomingCall(_ call: CallNotificationInfo,
                                    caller: SignalServiceAddress) {
        let thread = call.thread

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
            threadIdentifier = thread.uniqueId
        }

        let notificationBody: String
        switch call.offerMediaType {
        case .audio: notificationBody = NotificationStrings.incomingAudioCallBody
        case .video: notificationBody = NotificationStrings.incomingVideoCallBody
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.localCallId: call.localId.uuidString
        ]

        var interaction: INInteraction?
        if #available(iOS 15, *),
            previewType != .noNameNoPreview,
            let intent = thread.generateStartCallIntent(callerAddress: caller) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        notifyAsync { completion in
            self.adaptee.notify(category: .incomingCall,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                interaction: interaction,
                                sound: nil,
                                replacingIdentifier: call.localId.uuidString,
                                completion: completion)
        }
    }

    /// Classifies a timestamp based on how it should be included in a notification.
    ///
    /// In particular, a notification already comes with its own timestamp, so any information we put in has to be
    /// relevant (different enough from the notification's own timestamp to be useful) and absolute (because if a
    /// thirty-minute-old notification says "five minutes ago", that's not great).
    private enum TimestampClassification {
        case lastFewMinutes
        case last24Hours
        case lastWeek
        case other

        init(_ timestamp: Date) {
            switch -timestamp.timeIntervalSinceNow {
            case ..<0:
                owsFailDebug("Formatting a notification for an event in the future")
                self = .other
            case ...(5 * kMinuteInterval):
                self = .lastFewMinutes
            case ...kDayInterval:
                self = .last24Hours
            case ...kWeekInterval:
                self = .lastWeek
            default:
                self = .other
            }
        }
    }

    public func presentMissedCall(_ call: CallNotificationInfo,
                                  caller: SignalServiceAddress,
                                  sentAt timestamp: Date) {
        let thread = call.thread

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
            threadIdentifier = thread.uniqueId
        }

        let timestampClassification = TimestampClassification(timestamp)
        let timestampArgument: String
        switch timestampClassification {
        case .lastFewMinutes:
            // will be ignored
            timestampArgument = ""
        case .last24Hours:
            timestampArgument = DateUtil.formatDateAsTime(timestamp)
        case .lastWeek:
            timestampArgument = DateUtil.weekdayFormatter().string(from: timestamp)
        case .other:
            timestampArgument = DateUtil.monthAndDayFormatter().string(from: timestamp)
        }

        // We could build these localized string keys by interpolating the two pieces,
        // but then genstrings wouldn't pick them up.
        let notificationBodyFormat: String
        switch (call.offerMediaType, timestampClassification) {
        case (.audio, .lastFewMinutes):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_NOTIFICATION_BODY",
                comment: "notification body for a call that was just missed")
        case (.audio, .last24Hours):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_24_HOURS_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call in the last 24 hours. Embeds {{time}}, e.g. '3:30 PM'.")
        case (.audio, .lastWeek):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_WEEK_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from the last week. Embeds {{weekday}}, e.g. 'Monday'.")
        case (.audio, .other):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_PAST_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from more than a week ago. Embeds {{short date}}, e.g. '6/28'.")
        case (.video, .lastFewMinutes):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_NOTIFICATION_BODY",
                comment: "notification body for a call that was just missed")
        case (.video, .last24Hours):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_24_HOURS_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call in the last 24 hours. Embeds {{time}}, e.g. '3:30 PM'.")
        case (.video, .lastWeek):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_WEEK_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from the last week. Embeds {{weekday}}, e.g. 'Monday'.")
        case (.video, .other):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_PAST_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from more than a week ago. Embeds {{short date}}, e.g. '6/28'.")
        }
        let notificationBody = String(format: notificationBodyFormat, timestampArgument)

        let userInfo = userInfoForMissedCall(thread: thread, remoteAddress: caller)

        let category: AppNotificationCategory = (shouldShowActions
            ? .missedCallWithActions
            : .missedCallWithoutActions)

        var interaction: INInteraction?
        if #available(iOS 15, *),
            previewType != .noNameNoPreview,
            let intent = thread.generateStartCallIntent(callerAddress: caller) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: category,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                interaction: interaction,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString,
                                completion: completion)
        }
    }

    public func presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: CallNotificationInfo,
                                                                   caller: SignalServiceAddress) {

        let thread = call.thread

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
            threadIdentifier = thread.uniqueId
        }
        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody
        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId
        ]

        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .missedCallFromNoLongerVerifiedIdentity,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                interaction: nil,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString,
                                completion: completion)
        }
    }

    public func presentMissedCallBecauseOfNewIdentity(call: CallNotificationInfo,
                                                      caller: SignalServiceAddress) {

        let thread = call.thread

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
            threadIdentifier = thread.uniqueId
        }
        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody
        let userInfo = userInfoForMissedCall(thread: thread, remoteAddress: caller)

        let category: AppNotificationCategory = (shouldShowActions
            ? .missedCallWithActions
            : .missedCallWithoutActions)
        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: category,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                interaction: nil,
                                sound: sound,
                                replacingIdentifier: call.localId.uuidString,
                                completion: completion)
        }
    }

    private func userInfoForMissedCall(thread: TSThread, remoteAddress: SignalServiceAddress) -> [String: Any] {
        var userInfo: [String: Any] = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId
        ]
        if let uuid = remoteAddress.uuid {
            userInfo[AppNotificationUserInfoKey.callBackUuid] = uuid.uuidString
        }
        if let phoneNumber = remoteAddress.phoneNumber {
            userInfo[AppNotificationUserInfoKey.callBackPhoneNumber] = phoneNumber
        }
        return userInfo
    }

    public func isThreadMuted(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction).isMuted
    }

    public func canNotify(for incomingMessage: TSIncomingMessage,
                          thread: TSThread,
                          transaction: SDSAnyReadTransaction) -> Bool {
        guard !incomingMessage.isGroupStoryReply else { return false }

        guard isThreadMuted(thread, transaction: transaction) else {
            return true
        }

        guard thread.isGroupThread else { return false }

        guard let localAddress = TSAccountManager.localAddress else {
            owsFailDebug("Missing local address")
            return false
        }

        let mentionedAddresses = MentionFinder.mentionedAddresses(for: incomingMessage, transaction: transaction.unwrapGrdbRead)
        let localUserIsQuoted = incomingMessage.quotedMessage?.authorAddress.isEqualToAddress(localAddress) ?? false
        guard mentionedAddresses.contains(localAddress) || localUserIsQuoted else {
            if DebugFlags.internalLogging {
                Logger.info("Not notifying; no mention.")
            }
            return false
        }

        switch thread.mentionNotificationMode {
        case .default, .always:
            return true
        case .never:
            if DebugFlags.internalLogging {
                Logger.info("Not notifying; mentionNotificationMode .never.")
            }
            return false
        }
    }

    public func notifyUser(forIncomingMessage incomingMessage: TSIncomingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {

        guard canNotify(for: incomingMessage, thread: thread, transaction: transaction) else {
            if DebugFlags.internalLogging {
                Logger.info("Not notifying.")
            }
            return
        }

        // While batch processing, some of the necessary changes have not been committed.
        let rawMessageText = incomingMessage.previewText(transaction: transaction)

        let messageText = rawMessageText.filterStringForDisplay()

        let senderName = contactsManager.displayName(for: incomingMessage.authorAddress, transaction: transaction)

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
            case let groupThread as TSGroupThread:
                notificationTitle = String(format: NotificationStrings.incomingGroupMessageTitleFormat,
                                           senderName,
                                           groupThread.groupNameOrDefault)
            default:
                owsFailDebug("Invalid thread: \(thread.uniqueId)")
                return
            }

            threadIdentifier = thread.uniqueId
        }

        let notificationBody: String?
        switch previewType {
        case .noNameNoPreview, .nameNoPreview:
            notificationBody = NotificationStrings.genericIncomingMessageNotification
        case .namePreview:
            notificationBody = messageText
        }
        assert((notificationBody ?? notificationTitle) != nil)

        // Don't reply from lockscreen if anyone in this conversation is
        // "no longer verified".
        var didIdentityChange = false
        for address in thread.recipientAddresses(with: transaction) {
            if self.identityManager.verificationState(for: address,
                                                      transaction: transaction) == .noLongerVerified {
                didIdentityChange = true
                break
            }
        }

        let category: AppNotificationCategory
        if didIdentityChange {
            category = .incomingMessageFromNoLongerVerifiedIdentity
        } else if !shouldShowActions {
            category = .incomingMessageWithoutActions
        } else {
            category = (thread.canSendChatMessagesToThread()
                            ? .incomingMessageWithActions_CanReply
                            : .incomingMessageWithActions_CannotReply)
        }
        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.messageId: incomingMessage.uniqueId
        ]

        var interaction: INInteraction?
        if previewType != .noNameNoPreview,
           let intent = thread.generateSendMessageIntent(context: .incomingMessage(incomingMessage), transaction: transaction) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: category,
                                title: notificationTitle,
                                body: notificationBody ?? "",
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                interaction: interaction,
                                sound: sound,
                                completion: completion)
        }
    }

    public static var notifyOnMainThread: Bool {
        // The NSE can safely post notifications off the main thread;
        // the main app cannot.
        !CurrentAppContext().isNSE
    }
    public static let serialQueue = DispatchQueue(label: "org.signal.notificationPresenter")
    public static var notificationQueue: DispatchQueue { notifyOnMainThread ? .main : serialQueue }
    private var notificationQueue: DispatchQueue { Self.notificationQueue }

    private static let pendingTasks = PendingTasks(label: "Notifications")

    public static func pendingNotificationsPromise() -> Promise<Void> {
        // This promise blocks on all pending notifications already in flight,
        // but will not block on new notifications enqueued after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }

    private func notifyAsync(_ block: @escaping (@escaping NotificationCompletion) -> Void) {
        let pendingTask = Self.pendingTasks.buildPendingTask(label: "Notification")
        notificationQueue.async {
            block {
                pendingTask.complete()
            }
        }
    }

    private func notifyInAsyncCompletion(transaction: SDSAnyWriteTransaction,
                                         _ block: @escaping (@escaping NotificationCompletion) -> Void) {
        let pendingTask = Self.pendingTasks.buildPendingTask(label: "Notification")
        transaction.addAsyncCompletion(queue: notificationQueue) {
            block {
                pendingTask.complete()
            }
        }
    }

    public func notifyUser(forReaction reaction: OWSReaction,
                           onOutgoingMessage message: TSOutgoingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        guard !isThreadMuted(thread, transaction: transaction) else { return }

        // Reaction notifications only get displayed if we can
        // include the reaction details, otherwise we don't
        // disturb the user for a non-message
        guard previewType == .namePreview else { return }

        let senderName = contactsManager.displayName(for: reaction.reactor, transaction: transaction)

        let notificationTitle: String

        switch thread {
        case is TSContactThread:
            notificationTitle = senderName
        case let groupThread as TSGroupThread:
            notificationTitle = String(
                format: NotificationStrings.incomingGroupMessageTitleFormat,
                senderName,
                groupThread.groupNameOrDefault
            )
        default:
            owsFailDebug("unexpected thread: \(thread.uniqueId)")
            return
        }

        let notificationBody: String
        if let bodyDescription: String = {
            if let messageBody = message.plaintextBody(with: transaction.unwrapGrdbRead), !messageBody.isEmpty {
                return messageBody
            } else {
                return nil
            }
        }() {
            notificationBody = String(format: NotificationStrings.incomingReactionTextMessageFormat, reaction.emoji, bodyDescription)
        } else if message.isViewOnceMessage {
            notificationBody = String(format: NotificationStrings.incomingReactionViewOnceMessageFormat, reaction.emoji)
        } else if message.messageSticker != nil {
            notificationBody = String(format: NotificationStrings.incomingReactionStickerMessageFormat, reaction.emoji)
        } else if message.contactShare != nil {
            notificationBody = String(format: NotificationStrings.incomingReactionContactShareMessageFormat, reaction.emoji)
        } else if message.hasAttachments() {
            let mediaAttachments = message.mediaAttachments(with: transaction.unwrapGrdbRead)
            let firstAttachment = mediaAttachments.first

            if mediaAttachments.count > 1 {
                notificationBody = String(format: NotificationStrings.incomingReactionAlbumMessageFormat, reaction.emoji)
            } else if firstAttachment?.isImage == true {
                notificationBody = String(format: NotificationStrings.incomingReactionPhotoMessageFormat, reaction.emoji)
            } else if firstAttachment?.isAnimated == true || firstAttachment?.isLoopingVideo == true {
                notificationBody = String(format: NotificationStrings.incomingReactionGifMessageFormat, reaction.emoji)
            } else if firstAttachment?.isVideo == true {
                notificationBody = String(format: NotificationStrings.incomingReactionVideoMessageFormat, reaction.emoji)
            } else if firstAttachment?.isVoiceMessage == true {
                notificationBody = String(format: NotificationStrings.incomingReactionVoiceMessageFormat, reaction.emoji)
            } else if firstAttachment?.isAudio == true {
                notificationBody = String(format: NotificationStrings.incomingReactionAudioMessageFormat, reaction.emoji)
            } else {
                notificationBody = String(format: NotificationStrings.incomingReactionFileMessageFormat, reaction.emoji)
            }
        } else {
            notificationBody = String(format: NotificationStrings.incomingReactionFormat, reaction.emoji)
        }

        // Don't reply from lockscreen if anyone in this conversation is
        // "no longer verified".
        var didIdentityChange = false
        for address in thread.recipientAddresses(with: transaction) {
            if self.identityManager.verificationState(for: address,
                                                      transaction: transaction) == .noLongerVerified {
                didIdentityChange = true
                break
            }
        }

        let category: AppNotificationCategory
        if didIdentityChange {
            category = .incomingMessageFromNoLongerVerifiedIdentity
        } else if !shouldShowActions {
            category = .incomingMessageWithoutActions
        } else {
            category = (thread.canSendChatMessagesToThread()
                            ? .incomingReactionWithActions_CanReply
                            : .incomingReactionWithActions_CannotReply)
        }
        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.messageId: message.uniqueId,
            AppNotificationUserInfoKey.reactionId: reaction.uniqueId
        ]

        var interaction: INInteraction?
        if previewType != .noNameNoPreview,
           let intent = thread.generateSendMessageIntent(context: .senderAddress(reaction.reactor), transaction: transaction) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(
                category: category,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: thread.uniqueId,
                userInfo: userInfo,
                interaction: interaction,
                sound: sound,
                completion: completion
            )
        }
    }

    public func notifyForFailedSend(inThread thread: TSThread) {
        let notificationTitle: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
        }

        let notificationBody = NotificationStrings.failedToSendBody
        let threadId = thread.uniqueId
        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .infoOrErrorMessage,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: nil, // show ungrouped
                                userInfo: userInfo,
                                interaction: nil,
                                sound: sound,
                                completion: completion)
        }
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        // Fail debug on all devices. External devices should still log the error string.
        owsFailDebug("Fatal error occurred: \(errorString).")
        guard DebugFlags.testPopulationErrorAlerts else { return }

        let title = OWSLocalizedString("ERROR_NOTIFICATION_TITLE",
                                      comment: "Format string for an error alert notification title.")
        let messageFormat = OWSLocalizedString("ERROR_NOTIFICATION_MESSAGE_FORMAT",
                                              comment: "Format string for an error alert notification message. Embeds {{ error string }}")
        let message = String(format: messageFormat, errorString)

        notifyAsync { completion in
            self.adaptee.notify(
                category: .internalError,
                title: title,
                body: message,
                threadIdentifier: nil,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.submitDebugLogs.rawValue
                ],
                interaction: nil,
                sound: self.requestGlobalSound(),
                completion: completion)
        }
    }

    public func notifyForGroupCallSafetyNumberChange(inThread thread: TSThread) {
        let notificationTitle: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
        }

        let notificationBody = NotificationStrings.groupCallSafetyNumberChangeBody
        let threadId = thread.uniqueId
        let userInfo: [String: Any] = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showCallLobby.rawValue
        ]

        notifyAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.adaptee.notify(category: .infoOrErrorMessage,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: nil, // show ungrouped
                                userInfo: userInfo,
                                interaction: nil,
                                sound: sound,
                                completion: completion)
        }
    }

    public func notifyUser(forErrorMessage errorMessage: TSErrorMessage,
                           thread: TSThread,
                           transaction: SDSAnyWriteTransaction) {
        guard (errorMessage is OWSRecoverableDecryptionPlaceholder) == false else { return }

        switch errorMessage.errorType {
        case .noSession,
             .wrongTrustedIdentityKey,
             .invalidKeyException,
             .missingKeyId,
             .invalidMessage,
             .duplicateMessage,
             .invalidVersion,
             .nonBlockingIdentityChange,
             .unknownContactBlockOffer,
             .decryptionFailure,
             .groupCreationFailed:
            return
        case .sessionRefresh:
            notifyUser(forPreviewableInteraction: errorMessage as TSMessage,
                       thread: thread,
                       wantsSound: true,
                       transaction: transaction)
        }
    }

    public func notifyUser(forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
                           thread: TSThread,
                           wantsSound: Bool,
                           transaction: SDSAnyWriteTransaction) {
        guard !isThreadMuted(thread, transaction: transaction) else { return }

        let notificationTitle: String?
        let threadIdentifier: String?
        switch self.previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .namePreview, .nameNoPreview:
            notificationTitle = contactsManager.displayName(for: thread, transaction: transaction)
            threadIdentifier = thread.uniqueId
        }

        let notificationBody: String
        switch previewType {
        case .noNameNoPreview, .nameNoPreview:
            notificationBody = NotificationStrings.genericIncomingMessageNotification
        case .namePreview:
            notificationBody = previewableInteraction.previewText(transaction: transaction)
        }

        let isGroupCallMessage = previewableInteraction is OWSGroupCallMessage
        let preferredDefaultAction: AppNotificationAction = isGroupCallMessage ? .showCallLobby : .showThread

        let threadId = thread.uniqueId
        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.messageId: previewableInteraction.uniqueId,
            AppNotificationUserInfoKey.defaultAction: preferredDefaultAction.rawValue
        ]

        // Some types of generic messages (locally generated notifications) have a defacto
        // "sender". If so, generate an interaction so the notification renders as if it
        // is from that user.
        var interaction: INInteraction?
        if previewType != .noNameNoPreview {
            func wrapIntent(_ intent: INIntent) {
                let wrapper = INInteraction(intent: intent, response: nil)
                wrapper.direction = .incoming
                interaction = wrapper
            }

            if let infoMessage = previewableInteraction as? TSInfoMessage {
                switch infoMessage.messageType {
                case .typeGroupUpdate:
                    if let groupUpdateAuthor = infoMessage.groupUpdateSourceAddress,
                       let intent = thread.generateSendMessageIntent(context: .senderAddress(groupUpdateAuthor), transaction: transaction) {
                        wrapIntent(intent)
                    }
                case .userJoinedSignal:
                    if let thread = thread as? TSContactThread,
                       let intent = thread.generateSendMessageIntent(context: .senderAddress(thread.contactAddress), transaction: transaction) {
                        wrapIntent(intent)
                    }
                default:
                    break
                }
            } else if #available(iOS 15, *),
                      let callMessage = previewableInteraction as? OWSGroupCallMessage,
                      let callCreator = callMessage.creatorAddress,
                      let intent = thread.generateSendMessageIntent(context: .senderAddress(callCreator), transaction: transaction) {
                wrapIntent(intent)
            }
        }

        notifyInAsyncCompletion(transaction: transaction) { completion in
            let sound = wantsSound ? self.requestSound(thread: thread) : nil
            self.adaptee.notify(category: .infoOrErrorMessage,
                                title: notificationTitle,
                                body: notificationBody,
                                threadIdentifier: threadIdentifier,
                                userInfo: userInfo,
                                interaction: interaction,
                                sound: sound,
                                completion: completion)
        }
    }

    public func notifyUser(forThreadlessErrorMessage errorMessage: ThreadlessErrorMessage,
                           transaction: SDSAnyWriteTransaction) {
        let notificationBody = errorMessage.previewText(transaction: transaction)

        notifyInAsyncCompletion(transaction: transaction) { completion in
            self.adaptee.notify(category: .threadlessErrorMessage,
                                title: nil,
                                body: notificationBody,
                                threadIdentifier: nil,
                                userInfo: [:],
                                interaction: nil,
                                sound: self.requestGlobalSound(),
                                completion: completion)
        }
    }

    // This method is thread-safe.
    public func postGenericIncomingMessageNotification() -> Promise<Void> {
        adaptee.postGenericIncomingMessageNotification()
    }

    @objc
    public func cancelNotifications(threadId: String) {
        adaptee.cancelNotifications(threadId: threadId)
    }

    @objc
    public func cancelNotifications(messageId: String) {
        adaptee.cancelNotifications(messageId: messageId)
    }

    @objc
    public func cancelNotifications(reactionId: String) {
        adaptee.cancelNotifications(reactionId: reactionId)
    }

    @objc
    public func clearAllNotifications() {
        adaptee.clearAllNotifications()
    }

    // MARK: -

    private let unfairLock = UnfairLock()
    private var mostRecentNotifications = TruncatedList<UInt64>(maxLength: kAudioNotificationsThrottleCount)

    private func requestSound(thread: TSThread) -> OWSSound? {
        guard checkIfShouldPlaySound() else {
            return nil
        }

        return OWSSounds.notificationSound(for: thread)
    }

    private func requestGlobalSound() -> OWSSound? {
        checkIfShouldPlaySound() ? OWSSounds.globalNotificationSound() : nil
    }

    // This method is thread-safe.
    private func checkIfShouldPlaySound() -> Bool {
        guard CurrentAppContext().isMainAppAndActive else {
            Logger.info("[Notification Sounds] not playing sound, app inactive")
            return true
        }

        guard preferences.soundInForeground() else {
            Logger.info("[Notification Sounds] foreground sound disabled")
            return false
        }

        let now = NSDate.ows_millisecondTimeStamp()
        let recentThreshold = now - UInt64(kAudioNotificationsThrottleInterval * Double(kSecondInMs))

        return unfairLock.withLock {
            let recentNotifications = mostRecentNotifications.filter { $0 > recentThreshold }

            guard recentNotifications.count < kAudioNotificationsThrottleCount else {
                Logger.info("[Notification Sounds] sound throttled")
                return false
            }

            mostRecentNotifications.append(now)
            return true
        }
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

public protocol CallNotificationInfo {
    var thread: TSThread { get }
    var localId: UUID { get }
    var offerMediaType: TSRecentCallOfferType { get }
}
