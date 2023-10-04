//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
/// Our `NotificationActionHandler`s need slightly different integrations for UINotifications (iOS 9)
/// vs. UNUserNotifications (iOS 10+), but because they are integrated at separate system defined callbacks,
/// there is no need for an adapter pattern, and instead the appropriate NotificationActionHandler is
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
    case incomingGroupStoryReply
    case failedStorySend
    case transferRelaunch
    case deregistration
}

public enum AppNotificationAction: String, CaseIterable {
    case answerCall
    case callBack
    case declineCall
    case markAsRead
    case reply
    case showThread
    case showMyStories
    case reactWithThumbsUp
    case showCallLobby
    case submitDebugLogs
    case reregister
    case showChatList
}

public struct AppNotificationUserInfoKey {
    public static let threadId = "Signal.AppNotificationsUserInfoKey.threadId"
    public static let messageId = "Signal.AppNotificationsUserInfoKey.messageId"
    public static let reactionId = "Signal.AppNotificationsUserInfoKey.reactionId"
    public static let storyMessageId = "Signal.AppNotificationsUserInfoKey.storyMessageId"
    public static let storyTimestamp = "Signal.AppNotificationsUserInfoKey.storyTimestamp"
    public static let callBackAciString = "Signal.AppNotificationsUserInfoKey.callBackUuid"
    public static let callBackPhoneNumber = "Signal.AppNotificationsUserInfoKey.callBackPhoneNumber"
    public static let localCallId = "Signal.AppNotificationsUserInfoKey.localCallId"
    public static let isMissedCall = "Signal.AppNotificationsUserInfoKey.isMissedCall"
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
        case .incomingGroupStoryReply:
            return "Signal.AppNotificationCategory.incomingGroupStoryReply"
        case .failedStorySend:
            return "Signal.AppNotificationCategory.failedStorySend"
        case .transferRelaunch:
            return "Signal.AppNotificationCategory.transferRelaunch"
        case .deregistration:
            return "Signal.AppNotificationCategory.authErrorLogout"
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
        case .incomingGroupStoryReply:
            return [.reply]
        case .failedStorySend:
            return []
        case .transferRelaunch:
            return []
        case .deregistration:
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
        case .showMyStories:
            return "Signal.AppNotifications.Action.showMyStories"
        case .reactWithThumbsUp:
            return "Signal.AppNotifications.Action.reactWithThumbsUp"
        case .showCallLobby:
            return "Signal.AppNotifications.Action.showCallLobby"
        case .submitDebugLogs:
            return "Signal.AppNotifications.Action.submitDebugLogs"
        case .reregister:
            return "Signal.AppNotifications.Action.reregister"
        case .showChatList:
            return "Signal.AppNotifications.Action.showChatList"
        }
    }
}

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

// MARK: -

extension UserNotificationPresenter {
    var hasReceivedSyncMessageRecently: Bool {
        return DependenciesBridge.shared.deviceManager.hasReceivedSyncMessage(
            inLastSeconds: 60
        )
    }
}

// MARK: -

public class NotificationPresenter: NSObject, NotificationsProtocolSwift {
    private let presenter = UserNotificationPresenter(notifyQueue: NotificationPresenter.notificationQueue)

    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    var previewType: NotificationType {
        return preferences.notificationPreviewType
    }

    var shouldShowActions: Bool {
        return previewType == .namePreview
    }

    // MARK: - Notifications Permissions

    public func registerNotificationSettings() -> Guarantee<Void> {
        return presenter.registerNotificationSettings()
    }

    // MARK: - Calls

    public func presentIncomingCall(_ call: CallNotificationInfo,
                                    caller: SignalServiceAddress) {
        let thread = call.thread

        let notificationTitle: String?
        let threadIdentifier: String?
        let callerNameForGroupCall: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
            callerNameForGroupCall = nil
        case .nameNoPreview, .namePreview:
            (notificationTitle, callerNameForGroupCall) = databaseStorage.read { transaction in
                let threadName = contactsManager.displayName(for: thread, transaction: transaction)
                let callerNameForGroupCall: String?
                if thread.isGroupThread {
                    callerNameForGroupCall = contactsManager.displayName(for: caller, transaction: transaction)
                } else {
                    callerNameForGroupCall = nil
                }
                return (threadName, callerNameForGroupCall)
            }
            threadIdentifier = thread.uniqueId
        }

        let notificationBody: String
        if let callerNameForGroupCall = callerNameForGroupCall {
            notificationBody = String(format: NotificationStrings.incomingGroupCallBodyFormat, callerNameForGroupCall)
        } else if thread.isGroupThread {
            notificationBody = NotificationStrings.incomingGroupCallBodyAnonymous
        } else {
            switch call.offerMediaType {
            case .audio: notificationBody = NotificationStrings.incomingAudioCallBody
            case .video: notificationBody = NotificationStrings.incomingVideoCallBody
            }
        }

        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.localCallId: call.localId.uuidString
        ]

        var interaction: INInteraction?
        if previewType != .noNameNoPreview,
           let intent = thread.generateIncomingCallIntent(callerAddress: caller) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        performNotificationActionAsync { completion in
            self.presenter.notify(category: .incomingCall,
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
            timestampArgument = DateUtil.weekdayFormatter.string(from: timestamp)
        case .other:
            timestampArgument = DateUtil.monthAndDayFormatter.string(from: timestamp)
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
        if previewType != .noNameNoPreview,
           let intent = thread.generateIncomingCallIntent(callerAddress: caller) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        performNotificationActionAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.presenter.notify(category: category,
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

        performNotificationActionAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.presenter.notify(category: .missedCallFromNoLongerVerifiedIdentity,
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
        performNotificationActionAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.presenter.notify(category: category,
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
        if let aci = remoteAddress.aci {
            userInfo[AppNotificationUserInfoKey.callBackAciString] = aci.serviceIdUppercaseString
        }
        if let phoneNumber = remoteAddress.phoneNumber {
            userInfo[AppNotificationUserInfoKey.callBackPhoneNumber] = phoneNumber
        }
        userInfo[AppNotificationUserInfoKey.isMissedCall] = true
        return userInfo
    }

    // MARK: - Notify

    public func isThreadMuted(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction).isMuted
    }

    public func canNotify(
        for incomingMessage: TSIncomingMessage,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        guard isThreadMuted(thread, transaction: transaction) else {
            guard incomingMessage.isGroupStoryReply else { return true }

            guard
                let storyTimestamp = incomingMessage.storyTimestamp?.uint64Value,
                let storyAuthorAci = incomingMessage.storyAuthorAci?.wrappedAciValue
            else {
                return false
            }

            let localAci = tsAccountManager.localIdentifiers(transaction: transaction)?.aci

            // Always notify for replies to group stories you sent
            if storyAuthorAci == localAci { return true }

            // Always notify if you have been @mentioned
            if
                let mentionedAcis = incomingMessage.bodyRanges?.mentions.values,
                mentionedAcis.contains(where: { $0 == localAci }) {
                return true
            }

            // Notify people who did not author the story if they've previously replied to it
            return InteractionFinder.hasLocalUserReplied(
                storyTimestamp: storyTimestamp,
                storyAuthorAci: storyAuthorAci,
                transaction: transaction
            )
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

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) {
        notifyUserInternal(
            forIncomingMessage: incomingMessage,
            editTarget: nil,
            thread: thread,
            transaction: transaction
        )
    }

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        editTarget: TSIncomingMessage,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) {
        notifyUserInternal(
            forIncomingMessage: incomingMessage,
            editTarget: editTarget,
            thread: thread,
            transaction: transaction
        )
    }

    private func notifyUserInternal(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        editTarget: TSIncomingMessage?,
        thread: TSThread,
        transaction: SDSAnyReadTransaction) {

        guard canNotify(for: incomingMessage, thread: thread, transaction: transaction) else {
            if DebugFlags.internalLogging {
                Logger.info("Not notifying.")
            }
            return
        }

        // While batch processing, some of the necessary changes have not been committed.
        let rawMessageText = incomingMessage.notificationPreviewText(transaction)

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
                notificationTitle = String(
                    format: incomingMessage.isGroupStoryReply
                    ? NotificationStrings.incomingGroupStoryReplyTitleFormat
                    : NotificationStrings.incomingGroupMessageTitleFormat,
                    senderName,
                    groupThread.groupNameOrDefault
                )
            default:
                owsFailDebug("Invalid thread: \(thread.uniqueId)")
                return
            }

            threadIdentifier = thread.uniqueId
        }

        let notificationBody: String = {
            if thread.hasPendingMessageRequest(transaction: transaction) {
                return NotificationStrings.incomingMessageRequestNotification
            }

            switch previewType {
            case .noNameNoPreview, .nameNoPreview:
                return NotificationStrings.genericIncomingMessageNotification
            case .namePreview:
                return messageText
            }
        }()

        // Don't reply from lockscreen if anyone in this conversation is
        // "no longer verified".
        var didIdentityChange = false
        let identityManager = DependenciesBridge.shared.identityManager
        for address in thread.recipientAddresses(with: transaction) {
            if identityManager.verificationState(for: address, tx: transaction.asV2Read) == .noLongerVerified {
                didIdentityChange = true
                break
            }
        }

        let category: AppNotificationCategory
        if didIdentityChange {
            category = .incomingMessageFromNoLongerVerifiedIdentity
        } else if !shouldShowActions {
            category = .incomingMessageWithoutActions
        } else if incomingMessage.isGroupStoryReply {
            category = .incomingGroupStoryReply
        } else {
            category = (thread.canSendChatMessagesToThread()
                            ? .incomingMessageWithActions_CanReply
                            : .incomingMessageWithActions_CannotReply)
        }
        var userInfo: [AnyHashable: Any] = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.messageId: incomingMessage.uniqueId
        ]

        if let storyTimestamp = incomingMessage.storyTimestamp?.uint64Value {
            userInfo[AppNotificationUserInfoKey.storyTimestamp] = storyTimestamp
        }

        var interaction: INInteraction?
        if previewType != .noNameNoPreview,
           let intent = thread.generateSendMessageIntent(context: .incomingMessage(incomingMessage), transaction: transaction) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        performNotificationActionAsync { completion in
            let sound = (editTarget != nil) ? nil : self.requestSound(thread: thread)
            let notify = {
                self.presenter.notify(
                    category: category,
                    title: notificationTitle,
                    body: notificationBody,
                    threadIdentifier: threadIdentifier,
                    userInfo: userInfo,
                    interaction: interaction,
                    sound: sound,
                    completion: completion
                )
            }

            if let editTarget {
                self.presenter.replaceNotification(messageId: editTarget.uniqueId) { didReplaceNotification in
                    guard didReplaceNotification else {
                        completion()
                        return
                    }
                    Self.notificationQueue.async {
                        notify()
                    }
                }
            } else {
               notify()
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
            if let messageBody = message.notificationPreviewText(transaction).nilIfEmpty {
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
        let identityManager = DependenciesBridge.shared.identityManager
        for address in thread.recipientAddresses(with: transaction) {
            if identityManager.verificationState(for: address, tx: transaction.asV2Read) == .noLongerVerified {
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

        performNotificationActionAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.presenter.notify(
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

        performNotificationActionAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.presenter.notify(category: .infoOrErrorMessage,
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

        performNotificationActionAsync { completion in
            self.presenter.notify(
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

    public func notifyForGroupCallSafetyNumberChange(inThread thread: TSThread, presentAtJoin: Bool) {
        let notificationTitle: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
        case .nameNoPreview, .namePreview:
            notificationTitle = contactsManager.displayNameWithSneakyTransaction(thread: thread)
        }

        let notificationBody = (presentAtJoin
                                ? NotificationStrings.groupCallSafetyNumberChangeAtJoinBody
                                : NotificationStrings.groupCallSafetyNumberChangeBody)
        let threadId = thread.uniqueId
        let userInfo: [String: Any] = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showCallLobby.rawValue
        ]

        performNotificationActionAsync { completion in
            let sound = self.requestSound(thread: thread)
            self.presenter.notify(category: .infoOrErrorMessage,
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
            notifyUser(
                forTSMessage: errorMessage as TSMessage,
                thread: thread,
                wantsSound: true,
                transaction: transaction
            )
        }
    }

    public func notifyUser(
        forTSMessage message: TSMessage,
        thread: TSThread,
        wantsSound: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        notifyUser(
            tsInteraction: message,
            previewProvider: { tx in
                return message.notificationPreviewText(tx)
            },
            thread: thread,
            wantsSound: wantsSound,
            transaction: transaction
        )
    }

    public func notifyUser(
        forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
        thread: TSThread,
        wantsSound: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        notifyUser(
            tsInteraction: previewableInteraction,
            previewProvider: { tx in
                return previewableInteraction.previewText(transaction: tx)
            },
            thread: thread,
            wantsSound: wantsSound,
            transaction: transaction
        )
    }

    private func notifyUser(
        tsInteraction: TSInteraction,
        previewProvider: (SDSAnyWriteTransaction) -> String,
        thread: TSThread,
        wantsSound: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
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
            notificationBody = previewProvider(transaction)
        }

        let isGroupCallMessage = tsInteraction is OWSGroupCallMessage
        let preferredDefaultAction: AppNotificationAction = isGroupCallMessage ? .showCallLobby : .showThread

        let threadId = thread.uniqueId
        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId,
            AppNotificationUserInfoKey.messageId: tsInteraction.uniqueId,
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

            if let infoMessage = tsInteraction as? TSInfoMessage {
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
            } else if let callMessage = tsInteraction as? OWSGroupCallMessage,
                      let callCreator = callMessage.creatorAddress,
                      let intent = thread.generateSendMessageIntent(context: .senderAddress(callCreator), transaction: transaction) {
                wrapIntent(intent)
            }
        }

        performNotificationActionInAsyncCompletion(transaction: transaction) { completion in
            let sound = wantsSound ? self.requestSound(thread: thread) : nil
            self.presenter.notify(category: .infoOrErrorMessage,
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

        performNotificationActionInAsyncCompletion(transaction: transaction) { completion in
            self.presenter.notify(category: .threadlessErrorMessage,
                                title: nil,
                                body: notificationBody,
                                threadIdentifier: nil,
                                userInfo: [:],
                                interaction: nil,
                                sound: self.requestGlobalSound(),
                                completion: completion)
        }
    }

    public func notifyUser(
        forFailedStorySend storyMessage: StoryMessage,
        to thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        let storyName = StoryManager.storyName(for: thread)
        let conversationIdentifier = thread.uniqueId + "_failedStorySend"

        let handle = INPersonHandle(value: nil, type: .unknown)
        let image = thread.intentStoryAvatarImage(tx: transaction)
        let person: INPerson = {
            if #available(iOS 15, *) {
                return INPerson(
                    personHandle: handle,
                    nameComponents: nil,
                    displayName: storyName,
                    image: image,
                    contactIdentifier: nil,
                    customIdentifier: nil,
                    isMe: false,
                    suggestionType: .none
                )
            } else {
                return INPerson(
                    personHandle: handle,
                    nameComponents: nil,
                    displayName: storyName,
                    image: image,
                    contactIdentifier: nil,
                    customIdentifier: nil,
                    isMe: false
                )
            }
        }()

        let sendMessageIntent: INSendMessageIntent
        if #available(iOS 14, *) {
            sendMessageIntent = INSendMessageIntent(
                recipients: nil,
                outgoingMessageType: .outgoingMessageText,
                content: nil,
                speakableGroupName: INSpeakableString(spokenPhrase: storyName),
                conversationIdentifier: conversationIdentifier,
                serviceName: nil,
                sender: person
            )
        } else {
            sendMessageIntent = INSendMessageIntent(
                recipients: nil,
                content: nil,
                speakableGroupName: INSpeakableString(spokenPhrase: storyName),
                conversationIdentifier: conversationIdentifier,
                serviceName: nil,
                sender: person
            )
        }
        let interaction = INInteraction(intent: sendMessageIntent, response: nil)
        interaction.direction = .outgoing
        let notificationTitle = storyName
        let notificationBody = OWSLocalizedString(
            "STORY_SEND_FAILED_NOTIFICATION_BODY",
            comment: "Body for notification shown when a story fails to send."
        )
        let threadIdentifier = thread.uniqueId
        let storyMessageId = storyMessage.uniqueId

        performNotificationActionInAsyncCompletion(transaction: transaction) { completion in
            self.presenter.notify(
                category: .failedStorySend,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadIdentifier,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showMyStories.rawValue,
                    AppNotificationUserInfoKey.storyMessageId: storyMessageId
                ],
                interaction: interaction,
                sound: self.requestGlobalSound(),
                completion: completion
            )
        }
    }

    public func notifyUserToRelaunchAfterTransfer(completion: (() -> Void)? = nil) {
        let notificationBody = OWSLocalizedString(
            "TRANSFER_RELAUNCH_NOTIFICATION",
            comment: "Notification prompting the user to relaunch Signal after a device transfer completed."
        )
        performNotificationActionAsync { innerCompletion in
            self.presenter.notify(
                category: .transferRelaunch,
                title: nil,
                body: notificationBody,
                threadIdentifier: nil,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showChatList.rawValue
                ],
                interaction: nil,
                // Use a default sound so we don't read from
                // the db (which doesn't work until we relaunch)
                sound: .standard(.note),
                forceBeforeOnboarded: true,
                completion: {
                    innerCompletion()
                    completion?()
                }
            )
        }
    }

    public func notifyUserOfDeregistration(tx: DBWriteTransaction) {
        notifyUserOfDeregistration(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func notifyUserOfDeregistration(transaction: SDSAnyWriteTransaction) {
        let notificationBody = OWSLocalizedString(
            "DEREGISTRATION_NOTIFICATION",
            comment: "Notification warning the user that they have been de-registered."
        )
        performNotificationActionInAsyncCompletion(transaction: transaction) { completion in
            self.presenter.notify(
                category: .deregistration,
                title: nil,
                body: notificationBody,
                threadIdentifier: nil,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.reregister.rawValue
                ],
                interaction: nil,
                sound: self.requestGlobalSound(),
                completion: completion
            )
        }
    }

    /// Note that this method is not serialized with other notifications
    /// actions.
    public func postGenericIncomingMessageNotification() -> Promise<Void> {
        presenter.postGenericIncomingMessageNotification()
    }

    // MARK: - Cancellation

    public func cancelNotifications(threadId: String) {
        performNotificationActionAsync { completion in
            self.presenter.cancelNotifications(threadId: threadId, completion: completion)
        }
    }

    public func cancelNotifications(messageIds: [String]) {
        performNotificationActionAsync { completion in
            self.presenter.cancelNotifications(messageIds: messageIds, completion: completion)
        }
    }

    public func cancelNotifications(reactionId: String) {
        performNotificationActionAsync { completion in
            self.presenter.cancelNotifications(reactionId: reactionId, completion: completion)
        }
    }

    public func cancelNotificationsForMissedCalls(threadUniqueId: String) {
        performNotificationActionAsync { completion in
            self.presenter.cancelNotificationsForMissedCalls(withThreadUniqueId: threadUniqueId, completion: completion)
        }
    }

    public func cancelNotifications(for storyMessage: StoryMessage) {
        let storyMessageId = storyMessage.uniqueId
        performNotificationActionAsync { completion in
            self.presenter.cancelNotificationsForStoryMessage(withUniqueId: storyMessageId, completion: completion)
        }
    }

    public func clearAllNotifications() {
        presenter.clearAllNotifications()
    }

    // MARK: - Serialization

    private static let serialQueue = DispatchQueue(label: "org.signal.notifications.action")
    private static var notificationQueue: DispatchQueue {
        // The NSE can safely post notifications off the main thread, but the
        // main app cannot.
        if CurrentAppContext().isNSE {
            return serialQueue
        }

        return .main
    }
    private var notificationQueue: DispatchQueue { Self.notificationQueue }

    private static let pendingTasks = PendingTasks(label: "Notifications")

    public static func pendingNotificationsPromise() -> Promise<Void> {
        // This promise blocks on all pending notifications already in flight,
        // but will not block on new notifications enqueued after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }

    private func performNotificationActionAsync(
        _ block: @escaping (@escaping UserNotificationPresenter.NotificationActionCompletion) -> Void
    ) {
        let pendingTask = Self.pendingTasks.buildPendingTask(label: "NotificationAction")
        notificationQueue.async {
            block {
                pendingTask.complete()
            }
        }
    }

    private func performNotificationActionInAsyncCompletion(
        transaction: SDSAnyWriteTransaction,
        _ block: @escaping (@escaping UserNotificationPresenter.NotificationActionCompletion) -> Void
    ) {
        let pendingTask = Self.pendingTasks.buildPendingTask(label: "NotificationAction")
        transaction.addAsyncCompletion(queue: notificationQueue) {
            block {
                pendingTask.complete()
            }
        }
    }

    // MARK: -

    private let unfairLock = UnfairLock()
    private var mostRecentNotifications = TruncatedList<UInt64>(maxLength: kAudioNotificationsThrottleCount)

    private func requestSound(thread: TSThread) -> Sound? {
        checkIfShouldPlaySound() ? Sounds.notificationSoundForThread(thread) : nil
    }

    private func requestGlobalSound() -> Sound? {
        checkIfShouldPlaySound() ? Sounds.globalNotificationSound : nil
    }

    // This method is thread-safe.
    private func checkIfShouldPlaySound() -> Bool {
        guard CurrentAppContext().isMainAppAndActive else {
            Logger.info("[Notification Sounds] not playing sound, app inactive")
            return true
        }

        guard preferences.soundInForeground else {
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
