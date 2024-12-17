//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Intents
import LibSignalClient

/// There are two primary components in our system notification integration:
///
///     1. The `NotificationPresenterImpl` shows system notifications to the user.
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
    case missedCallWithActions
    case missedCallWithoutActions
    case missedCallFromNoLongerVerifiedIdentity
    case internalError
    case incomingGroupStoryReply
    case failedStorySend
    case transferRelaunch
    case deregistration
    case newDeviceLinked
}

public enum AppNotificationAction: String, CaseIterable {
    case callBack
    case markAsRead
    case reply
    case showThread
    case showMyStories
    case reactWithThumbsUp
    case showCallLobby
    case submitDebugLogs
    case reregister
    case showChatList
    case showLinkedDevices
}

public struct AppNotificationUserInfoKey {
    public static let roomId = "Signal.AppNotificationsUserInfoKey.roomId"
    public static let threadId = "Signal.AppNotificationsUserInfoKey.threadId"
    public static let messageId = "Signal.AppNotificationsUserInfoKey.messageId"
    public static let reactionId = "Signal.AppNotificationsUserInfoKey.reactionId"
    public static let storyMessageId = "Signal.AppNotificationsUserInfoKey.storyMessageId"
    public static let storyTimestamp = "Signal.AppNotificationsUserInfoKey.storyTimestamp"
    public static let callBackAciString = "Signal.AppNotificationsUserInfoKey.callBackUuid"
    public static let callBackPhoneNumber = "Signal.AppNotificationsUserInfoKey.callBackPhoneNumber"
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
        case .missedCallWithActions:
            return "Signal.AppNotificationCategory.missedCallWithActions"
        case .missedCallWithoutActions:
            return "Signal.AppNotificationCategory.missedCall"
        case .missedCallFromNoLongerVerifiedIdentity:
            return "Signal.AppNotificationCategory.missedCallFromNoLongerVerifiedIdentity"
        case .internalError:
            return "Signal.AppNotificationCategory.internalError"
        case .incomingGroupStoryReply:
            return "Signal.AppNotificationCategory.incomingGroupStoryReply"
        case .failedStorySend:
            return "Signal.AppNotificationCategory.failedStorySend"
        case .transferRelaunch:
            return "Signal.AppNotificationCategory.transferRelaunch"
        case .deregistration:
            return "Signal.AppNotificationCategory.authErrorLogout"
        case .newDeviceLinked:
            return "Signal.AppNotificationCategory.newDeviceLinked"
        }
    }

    var actions: [AppNotificationAction] {
        switch self {
        case .incomingMessageWithActions_CanReply:
            return [.markAsRead, .reply, .reactWithThumbsUp]
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
        case .missedCallWithActions:
            return [.callBack, .showThread]
        case .missedCallWithoutActions:
            return []
        case .missedCallFromNoLongerVerifiedIdentity:
            return []
        case .internalError:
            return []
        case .incomingGroupStoryReply:
            return [.reply]
        case .failedStorySend:
            return []
        case .transferRelaunch:
            return []
        case .deregistration:
            return []
        case .newDeviceLinked:
            return []
        }
    }
}

extension AppNotificationAction {
    var identifier: String {
        switch self {
        case .callBack:
            return "Signal.AppNotifications.Action.callBack"
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
        case .showLinkedDevices:
            return "Signal.AppNotifications.Action.showLinkedDevices"
        }
    }
}

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

// MARK: -

public class NotificationPresenterImpl: NotificationPresenter {
    private let presenter = UserNotificationPresenter()

    private var contactManager: any ContactManager { SSKEnvironment.shared.contactManagerRef }
    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorageRef }
    private var identityManager: any OWSIdentityManager { DependenciesBridge.shared.identityManager }
    private var preferences: Preferences { SSKEnvironment.shared.preferencesRef }
    private var tsAccountManager: any TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    public init() {
        SwiftSingletons.register(self)
    }

    func previewType(tx: SDSAnyReadTransaction) -> NotificationType {
        return preferences.notificationPreviewType(tx: tx)
    }

    static func shouldShowActions(for previewType: NotificationType) -> Bool {
        return previewType == .namePreview
    }

    // MARK: - Notifications Permissions

    public func registerNotificationSettings() async {
        return await presenter.registerNotificationSettings()
    }

    private func notificationSuppressionRuleIfMainAppAndActive() async -> NotificationSuppressionRule? {
        guard CurrentAppContext().isMainApp else {
            return nil
        }
        return await self._notificationSuppressionRuleIfMainAppAndActive()
    }

    @MainActor
    private func _notificationSuppressionRuleIfMainAppAndActive() async -> NotificationSuppressionRule? {
        guard CurrentAppContext().isMainAppAndActive else {
            return nil
        }
        return .some({ () -> NotificationSuppressionRule in
            switch CurrentAppContext().frontmostViewController() {
            case let conversationSplit as ConversationSplit:
                return conversationSplit.visibleThread.map {
                    return .messagesInThread(threadUniqueId: $0.uniqueId)
                } ?? .none
            case let storyGroupReply as StoryGroupReplier:
                return .groupStoryReplies(
                    threadUniqueId: storyGroupReply.threadUniqueId,
                    storyMessageTimestamp: storyGroupReply.storyMessage.timestamp
                )
            case is FailedStorySendDisplayController:
                return .failedStorySends
            default:
                return .none
            }
        }())
    }

    // MARK: - Calls

    private struct CallPreview {
        let notificationTitle: String
        let threadIdentifier: String
        let shouldShowActions: Bool
    }

    private func fetchCallPreview(thread: TSThread, tx: SDSAnyReadTransaction) -> CallPreview? {
        let previewType = self.previewType(tx: tx)
        switch previewType {
        case .noNameNoPreview:
            return nil
        case .nameNoPreview, .namePreview:
            return CallPreview(
                notificationTitle: contactManager.displayName(for: thread, transaction: tx),
                threadIdentifier: thread.uniqueId,
                shouldShowActions: Self.shouldShowActions(for: previewType)
            )
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

    public func notifyUserOfMissedCall(
        notificationInfo: CallNotificationInfo,
        offerMediaType: TSRecentCallOfferType,
        sentAt timestamp: Date,
        tx: SDSAnyReadTransaction
    ) {
        let thread = notificationInfo.thread
        let callPreview = fetchCallPreview(thread: thread, tx: tx)

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
        switch (offerMediaType, timestampClassification) {
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

        let userInfo = userInfoForMissedCall(thread: thread, remoteAci: notificationInfo.caller)

        let category: AppNotificationCategory = (
            callPreview?.shouldShowActions == true
            ? .missedCallWithActions
            : .missedCallWithoutActions
        )

        var interaction: INInteraction?
        if callPreview != nil, let intent = thread.generateIncomingCallIntent(callerAci: notificationInfo.caller, tx: tx) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: category,
                title: callPreview?.notificationTitle,
                body: notificationBody,
                threadIdentifier: callPreview?.threadIdentifier,
                userInfo: userInfo,
                interaction: interaction,
                soundQuery: .thread(threadUniqueId),
                replacingIdentifier: notificationInfo.groupingId.uuidString
            )
        }
    }

    public func notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(
        notificationInfo: CallNotificationInfo,
        tx: SDSAnyReadTransaction
    ) {
        let thread = notificationInfo.thread
        let callPreview = fetchCallPreview(thread: thread, tx: tx)

        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody
        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId
        ]

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .missedCallFromNoLongerVerifiedIdentity,
                title: callPreview?.notificationTitle,
                body: notificationBody,
                threadIdentifier: callPreview?.threadIdentifier,
                userInfo: userInfo,
                interaction: nil,
                soundQuery: .thread(threadUniqueId),
                replacingIdentifier: notificationInfo.groupingId.uuidString
            )
        }
    }

    public func notifyUserOfMissedCallBecauseOfNewIdentity(
        notificationInfo: CallNotificationInfo,
        tx: SDSAnyReadTransaction
    ) {
        let thread = notificationInfo.thread
        let callPreview = fetchCallPreview(thread: thread, tx: tx)

        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody
        let userInfo = userInfoForMissedCall(thread: thread, remoteAci: notificationInfo.caller)

        let category: AppNotificationCategory = (
            callPreview?.shouldShowActions == true
            ? .missedCallWithActions
            : .missedCallWithoutActions
        )

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: category,
                title: callPreview?.notificationTitle,
                body: notificationBody,
                threadIdentifier: callPreview?.threadIdentifier,
                userInfo: userInfo,
                interaction: nil,
                soundQuery: .thread(threadUniqueId),
                replacingIdentifier: notificationInfo.groupingId.uuidString
            )
        }
    }

    private func userInfoForMissedCall(thread: TSThread, remoteAci: Aci) -> [String: Any] {
        let userInfo: [String: Any] = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.callBackAciString: remoteAci.serviceIdUppercaseString,
            AppNotificationUserInfoKey.isMissedCall: true,
        ]
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
        if isThreadMuted(thread, transaction: transaction) {
            guard thread.isGroupThread else { return false }

            guard let localAddress = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
                owsFailDebug("Missing local address")
                return false
            }

            let mentionedAddresses = MentionFinder.mentionedAddresses(for: incomingMessage, transaction: transaction.unwrapGrdbRead)
            let localUserIsQuoted = incomingMessage.quotedMessage?.authorAddress.isEqualToAddress(localAddress) ?? false
            guard mentionedAddresses.contains(localAddress) || localUserIsQuoted else {
                return false
            }

            switch thread.mentionNotificationMode {
            case .default, .always:
                return true
            case .never:
                return false
            }
        } else if incomingMessage.isGroupStoryReply {
            guard
                let storyTimestamp = incomingMessage.storyTimestamp?.uint64Value,
                let storyAuthorAci = incomingMessage.storyAuthorAci?.wrappedAciValue
            else {
                return false
            }

            let localAci = tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aci

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
        } else {
            return true
        }
    }

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) {
        _notifyUser(
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
        _notifyUser(
            forIncomingMessage: incomingMessage,
            editTarget: editTarget,
            thread: thread,
            transaction: transaction
        )
    }

    private func _notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        editTarget: TSIncomingMessage?,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) {

        guard canNotify(for: incomingMessage, thread: thread, transaction: transaction) else {
            return
        }

        // While batch processing, some of the necessary changes have not been committed.
        let rawMessageText = incomingMessage.notificationPreviewText(transaction)

        let messageText = rawMessageText.filterStringForDisplay()

        let senderName = contactManager.displayName(for: incomingMessage.authorAddress, tx: transaction).resolvedValue()

        let previewType = self.previewType(tx: transaction)

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
        for address in thread.recipientAddresses(with: transaction) {
            if identityManager.verificationState(for: address, tx: transaction.asV2Read) == .noLongerVerified {
                didIdentityChange = true
                break
            }
        }

        let category: AppNotificationCategory
        if didIdentityChange {
            category = .incomingMessageFromNoLongerVerifiedIdentity
        } else if !Self.shouldShowActions(for: previewType) {
            category = .incomingMessageWithoutActions
        } else if incomingMessage.isGroupStoryReply {
            category = .incomingGroupStoryReply
        } else {
            category = (
                thread.canSendChatMessagesToThread()
                ? .incomingMessageWithActions_CanReply
                : .incomingMessageWithActions_CannotReply
            )
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

        let threadUniqueId = thread.uniqueId
        let editTargetUniqueId = editTarget?.uniqueId
        enqueueNotificationAction {
            if let editTargetUniqueId, await !self.presenter.replaceNotification(messageId: editTargetUniqueId) {
                // The original notification was already dismissed. Don't show the edited one either.
                return
            }
            await self.notifyViaPresenter(
                category: category,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadIdentifier,
                userInfo: userInfo,
                interaction: interaction,
                soundQuery: (editTargetUniqueId != nil) ? .none : .thread(threadUniqueId)
            )
        }
    }

    public func notifyUser(
        forReaction reaction: OWSReaction,
        onOutgoingMessage message: TSOutgoingMessage,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) {
        guard !isThreadMuted(thread, transaction: transaction) else { return }

        // Reaction notifications only get displayed if we can include the reaction
        // details, otherwise we don't disturb the user for a non-message
        let previewType = self.previewType(tx: transaction)
        guard previewType == .namePreview else {
            return
        }
        owsPrecondition(Self.shouldShowActions(for: previewType))

        let senderName = contactManager.displayName(for: reaction.reactor, tx: transaction).resolvedValue()

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
        } else if
            let messageRowId = message.sqliteRowId,
            let mediaAttachments = DependenciesBridge.shared.attachmentStore
                .fetchReferencedAttachments(
                    for: .messageBodyAttachment(messageRowId: messageRowId),
                    tx: transaction.asV2Read
                )
                .nilIfEmpty,
            let firstAttachment = mediaAttachments.first
        {
            let firstRenderingFlag = firstAttachment.reference.renderingFlag
            // Mime type is spoofable by the sender but for the purpose of showing notifications,
            // trust the sender (if they _intended_ to send an image, say they sent an image).
            let firstMimeType = firstAttachment.attachment.mimeType

            if mediaAttachments.count > 1 {
                notificationBody = String(format: NotificationStrings.incomingReactionAlbumMessageFormat, reaction.emoji)
            } else if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(firstMimeType) {
                notificationBody = String(format: NotificationStrings.incomingReactionGifMessageFormat, reaction.emoji)
            } else if MimeTypeUtil.isSupportedImageMimeType(firstMimeType) {
                notificationBody = String(format: NotificationStrings.incomingReactionPhotoMessageFormat, reaction.emoji)
            } else if
                MimeTypeUtil.isSupportedVideoMimeType(firstMimeType),
                firstRenderingFlag == .shouldLoop
            {
                notificationBody = String(format: NotificationStrings.incomingReactionGifMessageFormat, reaction.emoji)
            } else if MimeTypeUtil.isSupportedVideoMimeType(firstMimeType) {
                notificationBody = String(format: NotificationStrings.incomingReactionVideoMessageFormat, reaction.emoji)
            } else if firstRenderingFlag == .voiceMessage {
                notificationBody = String(format: NotificationStrings.incomingReactionVoiceMessageFormat, reaction.emoji)
            } else if MimeTypeUtil.isSupportedAudioMimeType(firstMimeType) {
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
            if identityManager.verificationState(for: address, tx: transaction.asV2Read) == .noLongerVerified {
                didIdentityChange = true
                break
            }
        }

        let category: AppNotificationCategory
        if didIdentityChange {
            category = .incomingMessageFromNoLongerVerifiedIdentity
        } else {
            category = (
                thread.canSendChatMessagesToThread()
                ? .incomingReactionWithActions_CanReply
                : .incomingReactionWithActions_CannotReply
            )
        }
        let userInfo = [
            AppNotificationUserInfoKey.threadId: thread.uniqueId,
            AppNotificationUserInfoKey.messageId: message.uniqueId,
            AppNotificationUserInfoKey.reactionId: reaction.uniqueId
        ]

        var interaction: INInteraction?
        if let intent = thread.generateSendMessageIntent(context: .senderAddress(reaction.reactor), transaction: transaction) {
            let wrapper = INInteraction(intent: intent, response: nil)
            wrapper.direction = .incoming
            interaction = wrapper
        }

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: category,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadUniqueId,
                userInfo: userInfo,
                interaction: interaction,
                soundQuery: .thread(threadUniqueId)
            )
        }
    }

    public func notifyUserOfFailedSend(inThread thread: TSThread) {
        let notificationTitle: String? = databaseStorage.read { tx in
            switch self.previewType(tx: tx) {
            case .noNameNoPreview:
                return nil
            case .nameNoPreview, .namePreview:
                return contactManager.displayName(for: thread, transaction: tx)
            }
        }

        let notificationBody = NotificationStrings.failedToSendBody
        let threadId = thread.uniqueId
        let userInfo = [
            AppNotificationUserInfoKey.threadId: threadId
        ]

        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .infoOrErrorMessage,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: nil, // show ungrouped
                userInfo: userInfo,
                interaction: nil,
                soundQuery: .thread(threadId)
            )
        }
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        // Fail debug on all devices. External devices should still log the error string.
        Logger.error("Fatal error occurred: \(errorString).")
        guard DebugFlags.testPopulationErrorAlerts else {
            return
        }

        let title = OWSLocalizedString(
            "ERROR_NOTIFICATION_TITLE",
            comment: "Format string for an error alert notification title."
        )
        let messageFormat = OWSLocalizedString(
            "ERROR_NOTIFICATION_MESSAGE_FORMAT",
            comment: "Format string for an error alert notification message. Embeds {{ error string }}"
        )
        let message = String(format: messageFormat, errorString)

        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .internalError,
                title: title,
                body: message,
                threadIdentifier: nil,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.submitDebugLogs.rawValue
                ],
                interaction: nil,
                soundQuery: .global
            )
        }
    }

    public func notifyForGroupCallSafetyNumberChange(
        callTitle: String,
        threadUniqueId: String?,
        roomId: Data?,
        presentAtJoin: Bool
    ) {
        let notificationTitle: String? = databaseStorage.read { tx in
            switch previewType(tx: tx) {
            case .noNameNoPreview:
                return nil
            case .nameNoPreview, .namePreview:
                return callTitle
            }
        }

        let notificationBody = (
            presentAtJoin
            ? NotificationStrings.groupCallSafetyNumberChangeAtJoinBody
            : NotificationStrings.groupCallSafetyNumberChangeBody
        )

        var userInfo: [String: Any] = [
            AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showCallLobby.rawValue
        ]
        if let threadUniqueId {
            userInfo[AppNotificationUserInfoKey.threadId] = threadUniqueId
        }
        if let roomId {
            userInfo[AppNotificationUserInfoKey.roomId] = roomId.base64EncodedString()
        }

        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .infoOrErrorMessage,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: nil, // show ungrouped
                userInfo: userInfo,
                interaction: nil,
                soundQuery: threadUniqueId.map({ .thread($0) }) ?? .global
            )
        }
    }

    public func scheduleNotifyForNewLinkedDevice() {
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .newDeviceLinked,
                title: OWSLocalizedString(
                    "LINKED_DEVICE_NOTIFICATION_TITLE",
                    comment: "Title for system notification when a new device is linked."
                ),
                body: String(
                    format: OWSLocalizedString(
                        "LINKED_DEVICE_NOTIFICATION_BODY",
                        comment: "Body for system notification when a new device is linked. Embeds {{ time the device was linked }}"
                    ),
                    Date().formatted(date: .omitted, time: .shortened)
                ),
                threadIdentifier: nil,
                userInfo: [AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showLinkedDevices.rawValue],
                interaction: nil,
                soundQuery: .global
            )
        }
    }

    public func notifyUser(
        forErrorMessage errorMessage: TSErrorMessage,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
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

        let previewType = self.previewType(tx: transaction)

        let notificationTitle: String?
        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            notificationTitle = nil
            threadIdentifier = nil
        case .namePreview, .nameNoPreview:
            notificationTitle = contactManager.displayName(for: thread, transaction: transaction)
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
                guard let localIdentifiers = tsAccountManager.localIdentifiers(
                    tx: transaction.asV2Read
                ) else {
                    owsFailDebug("Missing local identifiers!")
                    return
                }
                switch infoMessage.messageType {
                case .typeGroupUpdate:
                    let groupUpdateAuthor: SignalServiceAddress?
                    switch infoMessage.groupUpdateMetadata(localIdentifiers: localIdentifiers) {
                    case .legacyRawString, .nonGroupUpdate:
                        groupUpdateAuthor = nil
                    case .newGroup(_, let updateMetadata), .modelDiff(_, _, let updateMetadata):
                        switch updateMetadata.source {
                        case .unknown, .localUser:
                            groupUpdateAuthor = nil
                        case .legacyE164(let e164):
                            groupUpdateAuthor = .legacyAddress(serviceId: nil, phoneNumber: e164.stringValue)
                        case .aci(let aci):
                            groupUpdateAuthor = .init(aci)
                        case .rejectedInviteToPni(let pni):
                            groupUpdateAuthor = .init(pni)
                        }
                    case .precomputed(let persistableGroupUpdateItemsWrapper):
                        groupUpdateAuthor = persistableGroupUpdateItemsWrapper
                            .asSingleUpdateItem?.senderForNotification
                    }
                    if
                        let groupUpdateAuthor,
                        let intent = thread.generateSendMessageIntent(context: .senderAddress(groupUpdateAuthor), transaction: transaction)
                    {
                        wrapIntent(intent)
                    }
                case .userJoinedSignal:
                    if
                        let thread = thread as? TSContactThread,
                        let intent = thread.generateSendMessageIntent(context: .senderAddress(thread.contactAddress), transaction: transaction)
                    {
                        wrapIntent(intent)
                    }
                default:
                    break
                }
            } else if
                let callMessage = tsInteraction as? OWSGroupCallMessage,
                let callCreator = callMessage.creatorAci?.wrappedAciValue,
                let intent = thread.generateSendMessageIntent(context: .senderAddress(SignalServiceAddress(callCreator)), transaction: transaction)
            {
                wrapIntent(intent)
            }
        }

        enqueueNotificationAction(afterCommitting: transaction) {
            await self.notifyViaPresenter(
                category: .infoOrErrorMessage,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadIdentifier,
                userInfo: userInfo,
                interaction: interaction,
                soundQuery: wantsSound ? .thread(threadId) : .none
            )
        }
    }

    public func notifyUser(
        forFailedStorySend storyMessage: StoryMessage,
        to thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        guard StoryManager.areStoriesEnabled(transaction: transaction) else {
            return
        }

        let storyName = StoryManager.storyName(for: thread)
        let conversationIdentifier = thread.uniqueId + "_failedStorySend"

        let handle = INPersonHandle(value: nil, type: .unknown)
        let image = thread.intentStoryAvatarImage(tx: transaction)
        let person = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: storyName,
            image: image,
            contactIdentifier: nil,
            customIdentifier: nil,
            isMe: false,
            suggestionType: .none
        )

        let sendMessageIntent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: storyName),
            conversationIdentifier: conversationIdentifier,
            serviceName: nil,
            sender: person,
            attachments: nil
        )
        let interaction = INInteraction(intent: sendMessageIntent, response: nil)
        interaction.direction = .outgoing
        let notificationTitle = storyName
        let notificationBody = OWSLocalizedString(
            "STORY_SEND_FAILED_NOTIFICATION_BODY",
            comment: "Body for notification shown when a story fails to send."
        )
        let threadIdentifier = thread.uniqueId
        let storyMessageId = storyMessage.uniqueId

        enqueueNotificationAction(afterCommitting: transaction) {
            await self.notifyViaPresenter(
                category: .failedStorySend,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadIdentifier,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.showMyStories.rawValue,
                    AppNotificationUserInfoKey.storyMessageId: storyMessageId
                ],
                interaction: interaction,
                soundQuery: .global
            )
        }
    }

    public func notifyUserToRelaunchAfterTransfer(completion: @escaping () -> Void) {
        let notificationBody = OWSLocalizedString(
            "TRANSFER_RELAUNCH_NOTIFICATION",
            comment: "Notification prompting the user to relaunch Signal after a device transfer completed."
        )
        enqueueNotificationAction {
            await self.notifyViaPresenter(
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
                soundQuery: .constant(.standard(.note)),
                forceBeforeRegistered: true
            )
            completion()
        }
    }

    public func notifyUserOfDeregistration(tx: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        let notificationBody = OWSLocalizedString(
            "DEREGISTRATION_NOTIFICATION",
            comment: "Notification warning the user that they have been de-registered."
        )
        enqueueNotificationAction(afterCommitting: sdsTx) {
            await self.notifyViaPresenter(
                category: .deregistration,
                title: nil,
                body: notificationBody,
                threadIdentifier: nil,
                userInfo: [
                    AppNotificationUserInfoKey.defaultAction: AppNotificationAction.reregister.rawValue
                ],
                interaction: nil,
                soundQuery: .global
            )
        }
    }

    private enum SoundQuery {
        case none
        case global
        case thread(String)
        case constant(Sound)
    }

    private func notifyViaPresenter(
        category: AppNotificationCategory,
        title: String?,
        body: String,
        threadIdentifier: String?,
        userInfo: [AnyHashable: Any],
        interaction: INInteraction?,
        soundQuery: SoundQuery,
        replacingIdentifier: String? = nil,
        forceBeforeRegistered: Bool = false
    ) async {
        let notificationSuppressionRule = await self.notificationSuppressionRuleIfMainAppAndActive()
        let sound: Sound?
        switch soundQuery {
        case .none:
            sound = nil
        case .global:
            sound = self.requestGlobalSound(isMainAppAndActive: notificationSuppressionRule != nil)
        case .thread(let threadUniqueId):
            sound = self.requestSound(forThreadUniqueId: threadUniqueId, isMainAppAndActive: notificationSuppressionRule != nil)
        case .constant(let constantSound):
            sound = constantSound
        }
        await self.presenter.notify(
            category: category,
            title: title,
            body: body,
            threadIdentifier: threadIdentifier,
            userInfo: userInfo,
            interaction: interaction,
            sound: sound,
            replacingIdentifier: replacingIdentifier,
            forceBeforeRegistered: forceBeforeRegistered,
            isMainAppAndActive: notificationSuppressionRule != nil,
            notificationSuppressionRule: notificationSuppressionRule ?? .none
        )
    }

    // MARK: - Cancellation

    public func cancelNotifications(threadId: String) {
        enqueueNotificationAction {
            await self.presenter.cancelNotifications(threadId: threadId)
        }
    }

    public func cancelNotifications(messageIds: [String]) {
        enqueueNotificationAction {
            await self.presenter.cancelNotifications(messageIds: messageIds)
        }
    }

    public func cancelNotifications(reactionId: String) {
        enqueueNotificationAction {
            await self.presenter.cancelNotifications(reactionId: reactionId)
        }
    }

    public func cancelNotificationsForMissedCalls(threadUniqueId: String) {
        enqueueNotificationAction {
            await self.presenter.cancelNotificationsForMissedCalls(withThreadUniqueId: threadUniqueId)
        }
    }

    public func cancelNotifications(for storyMessage: StoryMessage) {
        let storyMessageId = storyMessage.uniqueId
        enqueueNotificationAction {
            await self.presenter.cancelNotificationsForStoryMessage(withUniqueId: storyMessageId)
        }
    }

    public func clearAllNotifications() {
        presenter.clearAllNotifications()
    }

    public func clearAllNotificationsExceptNewLinkedDevices() {
        Self.clearAllNotificationsExceptNewLinkedDevices()
    }

    public static func clearAllNotificationsExceptNewLinkedDevices() {
        UserNotificationPresenter.clearAllNotificationsExceptNewLinkedDevices()
    }

    // MARK: - Serialization

    private static let pendingTasks = PendingTasks(label: "Notifications")

    public static func pendingNotificationsPromise() -> Promise<Void> {
        // This promise blocks on all pending notifications already in flight,
        // but will not block on new notifications enqueued after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }

    private let mostRecentTask = AtomicValue<Task<Void, Never>?>(nil, lock: .init())

    private func enqueueNotificationAction(afterCommitting tx: SDSAnyWriteTransaction? = nil, _ block: @escaping () async -> Void) {
        let startTime = CACurrentMediaTime()
        let pendingTask = Self.pendingTasks.buildPendingTask(label: "NotificationAction")
        let commitGuarantee = tx.map {
            let (guarantee, future) = Guarantee<Void>.pending()
            $0.addAsyncCompletionOffMain { future.resolve() }
            return guarantee
        }
        self.mostRecentTask.update {
            let oldTask = $0
            $0 = Task {
                defer { pendingTask.complete() }
                await oldTask?.value
                await commitGuarantee?.awaitable()
                let queueTime = CACurrentMediaTime()
                await block()
                let endTime = CACurrentMediaTime()

                let tooLargeThreshold: TimeInterval = 2
                if endTime - startTime >= tooLargeThreshold {
                    let formattedQueueDuration = String(format: "%.2f", queueTime - startTime)
                    let formattedNotifyDuration = String(format: "%.2f", endTime - queueTime)
                    Logger.warn("Couldn't post notification within \(tooLargeThreshold) seconds; \(formattedQueueDuration)s + \(formattedNotifyDuration)s")
                }
            }
        }
    }

    // MARK: -

    private let unfairLock = UnfairLock()
    private var mostRecentNotifications = TruncatedList<UInt64>(maxLength: kAudioNotificationsThrottleCount)

    private func requestSound(forThreadUniqueId threadUniqueId: String, isMainAppAndActive: Bool) -> Sound? {
        return checkIfShouldPlaySound(isMainAppAndActive: isMainAppAndActive) ? Sounds.notificationSoundWithSneakyTransaction(forThreadUniqueId: threadUniqueId) : nil
    }

    private func requestGlobalSound(isMainAppAndActive: Bool) -> Sound? {
        return checkIfShouldPlaySound(isMainAppAndActive: isMainAppAndActive) ? Sounds.globalNotificationSound : nil
    }

    private func checkIfShouldPlaySound(isMainAppAndActive: Bool) -> Bool {
        guard isMainAppAndActive else {
            return true
        }

        guard preferences.soundInForeground else {
            return false
        }

        let now = NSDate.ows_millisecondTimeStamp()
        let recentThreshold = now - UInt64(kAudioNotificationsThrottleInterval * Double(kSecondInMs))

        return unfairLock.withLock {
            let recentNotifications = mostRecentNotifications.filter { $0 > recentThreshold }

            guard recentNotifications.count < kAudioNotificationsThrottleCount else {
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
