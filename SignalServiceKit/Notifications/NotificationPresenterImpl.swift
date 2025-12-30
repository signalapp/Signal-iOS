//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Intents
public import LibSignalClient

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

/// Represents "custom" notification actions. These are the ones that appear
/// when long-pressing a notification. Their identifiers (rawValues) are
/// passed to iOS via UNNotificationAction.
///
/// These are persisted (via notifications) and must remain stable.
public enum AppNotificationAction: String {
    case callBack = "Signal.AppNotifications.Action.callBack"
    case markAsRead = "Signal.AppNotifications.Action.markAsRead"
    case reply = "Signal.AppNotifications.Action.reply"
    case showThread = "Signal.AppNotifications.Action.showThread"
    case reactWithThumbsUp = "Signal.AppNotifications.Action.reactWithThumbsUp"
}

/// Represents "default" notification actions. These happen when you tap a
/// notification to launch Signal. These are a Signal concept -- they are
/// stored inside a notification's userInfo.
///
/// These are persisted (via notifications) and must remain stable.
public enum AppNotificationDefaultAction: String {
    case showThread
    case showMyStories
    case showCallLobby
    case submitDebugLogs
    case reregister
    case showChatList
    case showLinkedDevices
    case showBackupsSettings
    case listMediaIntegrityCheck
}

public struct AppNotificationUserInfo {
    public var callBackAci: Aci?
    public var callBackPhoneNumber: String?
    public var defaultAction: AppNotificationDefaultAction?
    public var isMissedCall: Bool?
    public var messageId: String?
    public var reactionId: String?
    public var roomId: Data?
    public var storyMessageId: String?
    public var storyTimestamp: UInt64?
    public var threadId: String?
    public var voteAuthorServiceIdBinary: Data?

    public init() {
    }

    public init(_ userInfo: [AnyHashable: Any]) {
        self.callBackAci = (userInfo[UserInfoKey.callBackAciString] as? String).flatMap {
            let result = Aci.parseFrom(aciString: $0)
            owsAssertDebug(result != nil, "Couldn't parse callBackAciString.")
            return result
        }
        self.callBackPhoneNumber = userInfo[UserInfoKey.callBackPhoneNumber] as? String
        self.defaultAction = (userInfo[UserInfoKey.defaultAction] as? String).flatMap {
            let result = AppNotificationDefaultAction(rawValue: $0)
            owsAssertDebug(result != nil, "Couldn't parse default action. Did the identifiers change?")
            return result
        }
        self.isMissedCall = userInfo[UserInfoKey.isMissedCall] as? Bool
        self.messageId = userInfo[UserInfoKey.messageId] as? String
        self.reactionId = userInfo[UserInfoKey.reactionId] as? String
        self.roomId = (userInfo[UserInfoKey.roomId] as? String).flatMap {
            let result = Data(base64Encoded: $0)
            owsAssertDebug(result != nil, "Couldn't parse roomId.")
            return result
        }
        self.storyMessageId = userInfo[UserInfoKey.storyMessageId] as? String
        self.storyTimestamp = userInfo[UserInfoKey.storyTimestamp] as? UInt64
        self.threadId = userInfo[UserInfoKey.threadId] as? String
        self.voteAuthorServiceIdBinary = userInfo[UserInfoKey.voteAuthorServiceIdBinary] as? Data
    }

    private enum UserInfoKey {
        static let callBackAciString = "Signal.AppNotificationsUserInfoKey.callBackUuid"
        static let callBackPhoneNumber = "Signal.AppNotificationsUserInfoKey.callBackPhoneNumber"
        static let defaultAction = "Signal.AppNotificationsUserInfoKey.defaultAction"
        static let isMissedCall = "Signal.AppNotificationsUserInfoKey.isMissedCall"
        static let messageId = "Signal.AppNotificationsUserInfoKey.messageId"
        static let reactionId = "Signal.AppNotificationsUserInfoKey.reactionId"
        static let roomId = "Signal.AppNotificationsUserInfoKey.roomId"
        static let storyMessageId = "Signal.AppNotificationsUserInfoKey.storyMessageId"
        static let storyTimestamp = "Signal.AppNotificationsUserInfoKey.storyTimestamp"
        static let threadId = "Signal.AppNotificationsUserInfoKey.threadId"
        static let voteAuthorServiceIdBinary = "Signal.AppNotificationsUserInfoKey.voteAuthorServiceIdBinary"
    }

    func build() -> [String: Any] {
        var result = [String: Any]()
        if let callBackAci {
            result[UserInfoKey.callBackAciString] = callBackAci.serviceIdString
        }
        if let callBackPhoneNumber {
            result[UserInfoKey.callBackPhoneNumber] = callBackPhoneNumber
        }
        if let defaultAction {
            result[UserInfoKey.defaultAction] = defaultAction.rawValue
        }
        if let isMissedCall {
            result[UserInfoKey.isMissedCall] = isMissedCall
        }
        if let messageId {
            result[UserInfoKey.messageId] = messageId
        }
        if let reactionId {
            result[UserInfoKey.reactionId] = reactionId
        }
        if let roomId {
            result[UserInfoKey.roomId] = roomId.base64EncodedString()
        }
        if let storyMessageId {
            result[UserInfoKey.storyMessageId] = storyMessageId
        }
        if let storyTimestamp {
            result[UserInfoKey.storyTimestamp] = storyTimestamp
        }
        if let threadId {
            result[UserInfoKey.threadId] = threadId
        }
        if let voteAuthorServiceIdBinary {
            result[UserInfoKey.voteAuthorServiceIdBinary] = voteAuthorServiceIdBinary
        }
        return result
    }
}

// MARK: -

public enum AppNotificationCategory: String, CaseIterable {
    case incomingMessageWithActions_CanReply = "Signal.AppNotificationCategory.incomingMessageWithActions"
    case incomingMessageWithActions_CannotReply = "Signal.AppNotificationCategory.incomingMessageWithActionsNoReply"
    case incomingMessageWithoutActions = "Signal.AppNotificationCategory.incomingMessage"
    case incomingMessageFromNoLongerVerifiedIdentity = "Signal.AppNotificationCategory.incomingMessageFromNoLongerVerifiedIdentity"
    case incomingReactionWithActions_CanReply = "Signal.AppNotificationCategory.incomingReactionWithActions"
    case incomingReactionWithActions_CannotReply = "Signal.AppNotificationCategory.incomingReactionWithActionsNoReply"
    case infoOrErrorMessage = "Signal.AppNotificationCategory.infoOrErrorMessage"
    case missedCallWithActions = "Signal.AppNotificationCategory.missedCallWithActions"
    case missedCallWithoutActions = "Signal.AppNotificationCategory.missedCall"
    case missedCallFromNoLongerVerifiedIdentity = "Signal.AppNotificationCategory.missedCallFromNoLongerVerifiedIdentity"
    case internalError = "Signal.AppNotificationCategory.internalError"
    case incomingGroupStoryReply = "Signal.AppNotificationCategory.incomingGroupStoryReply"
    case failedStorySend = "Signal.AppNotificationCategory.failedStorySend"
    case transferRelaunch = "Signal.AppNotificationCategory.transferRelaunch"
    case deregistration = "Signal.AppNotificationCategory.authErrorLogout"
    case newDeviceLinked = "Signal.AppNotificationCategory.newDeviceLinked"
    case backupsEnabled = "Signal.AppNotificationCategory.backupsEnabled"
    case backupsMediaTierQuotaConsumed = "Signal.AppNotificationCategory.backupsMediaTierQuotaConsumed"
    case listMediaIntegrityCheckFailure = "Signal.AppNotificationCategory.listMediaIntegrityCheckFailure"
    case pollEndNotification = "Signal.AppNotificationCategory.pollEndNotification"
    case pollVoteNotification = "Signal.AppNotificationCategory.pollVoteNotification"

    var shouldClearOnAppActivate: Bool {
        switch self {
        case
            .incomingMessageWithActions_CanReply,
            .incomingMessageWithActions_CannotReply,
            .incomingMessageWithoutActions,
            .incomingMessageFromNoLongerVerifiedIdentity,
            .incomingReactionWithActions_CanReply,
            .incomingReactionWithActions_CannotReply,
            .infoOrErrorMessage,
            .missedCallWithActions,
            .missedCallWithoutActions,
            .missedCallFromNoLongerVerifiedIdentity,
            .incomingGroupStoryReply,
            .failedStorySend,
            .transferRelaunch,
            .deregistration,
            .pollEndNotification,
            .pollVoteNotification:
            return true
        case
            .newDeviceLinked,
            .backupsEnabled,
            .backupsMediaTierQuotaConsumed,
            .listMediaIntegrityCheckFailure,
            .internalError:
            return false
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
        case .backupsEnabled:
            return []
        case .backupsMediaTierQuotaConsumed:
            return []
        case .listMediaIntegrityCheckFailure:
            return []
        case .pollEndNotification:
            return []
        case .pollVoteNotification:
            return []
        }
    }
}

// MARK: -

let kAudioNotificationsThrottleCount = 2
let kAudioNotificationsThrottleInterval: TimeInterval = 5

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

    func previewType(tx: DBReadTransaction) -> NotificationType {
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
            case let linkAndSyncProgressUI as LinkAndSyncProgressUI where linkAndSyncProgressUI.shouldSuppressNotifications:
                return .all
            case let conversationSplit as ConversationSplit:
                return conversationSplit.visibleThread.map {
                    return .messagesInThread(threadUniqueId: $0.uniqueId)
                } ?? .none
            case let storyGroupReply as StoryGroupReplier:
                return .groupStoryReplies(
                    threadUniqueId: storyGroupReply.threadUniqueId,
                    storyMessageTimestamp: storyGroupReply.storyMessage.timestamp,
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
        let notificationTitle: ResolvableValue<String>
        let threadIdentifier: String
        let shouldShowActions: Bool
    }

    private func fetchCallPreview(thread: NotifiableThread, tx: DBReadTransaction) -> CallPreview? {
        let previewType = self.previewType(tx: tx)
        return self.notificationTitle(
            for: thread,
            senderAddress: nil,
            isGroupStoryReply: false,
            previewType: previewType,
            tx: tx,
        ).map {
            return CallPreview(
                notificationTitle: $0,
                threadIdentifier: thread.rawValue.uniqueId,
                shouldShowActions: Self.shouldShowActions(for: previewType),
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
            case ...(5 * .minute):
                self = .lastFewMinutes
            case ...(.day):
                self = .last24Hours
            case ...(.week):
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
        tx: DBReadTransaction,
    ) {
        let thread = notificationInfo.thread
        let callPreview = fetchCallPreview(thread: .individualThread(thread), tx: tx)

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
                comment: "notification body for a call that was just missed",
            )
        case (.audio, .last24Hours):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_24_HOURS_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call in the last 24 hours. Embeds {{time}}, e.g. '3:30 PM'.",
            )
        case (.audio, .lastWeek):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_WEEK_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from the last week. Embeds {{weekday}}, e.g. 'Monday'.",
            )
        case (.audio, .other):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_AUDIO_MISSED_PAST_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from more than a week ago. Embeds {{short date}}, e.g. '6/28'.",
            )
        case (.video, .lastFewMinutes):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_NOTIFICATION_BODY",
                comment: "notification body for a call that was just missed",
            )
        case (.video, .last24Hours):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_24_HOURS_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call in the last 24 hours. Embeds {{time}}, e.g. '3:30 PM'.",
            )
        case (.video, .lastWeek):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_WEEK_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from the last week. Embeds {{weekday}}, e.g. 'Monday'.",
            )
        case (.video, .other):
            notificationBodyFormat = OWSLocalizedString(
                "CALL_VIDEO_MISSED_PAST_NOTIFICATION_BODY_FORMAT",
                comment: "notification body for a missed call from more than a week ago. Embeds {{short date}}, e.g. '6/28'.",
            )
        }
        let notificationBody = String(format: notificationBodyFormat, timestampArgument)

        let userInfo = userInfoForMissedCall(thread: thread, remoteAci: notificationInfo.caller)

        let category: AppNotificationCategory = (
            callPreview?.shouldShowActions == true
                ? .missedCallWithActions
                : .missedCallWithoutActions,
        )

        var intent: ResolvableValue<INIntent>?
        if callPreview != nil {
            intent = thread.generateIncomingCallIntent(callerAci: notificationInfo.caller, tx: tx)
        }

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction(afterCommitting: tx) {
            await self.notifyViaPresenter(
                category: category,
                title: callPreview?.notificationTitle,
                body: notificationBody,
                threadIdentifier: callPreview?.threadIdentifier,
                userInfo: userInfo,
                intent: intent.map { ($0, .incoming) },
                soundQuery: .thread(threadUniqueId),
                replacingIdentifier: notificationInfo.groupingId.uuidString,
            )
        }
    }

    public func notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(
        notificationInfo: CallNotificationInfo,
        tx: DBWriteTransaction,
    ) {
        let thread = notificationInfo.thread
        let callPreview = fetchCallPreview(thread: .individualThread(thread), tx: tx)

        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = thread.uniqueId

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction(afterCommitting: tx) {
            await self.notifyViaPresenter(
                category: .missedCallFromNoLongerVerifiedIdentity,
                title: callPreview?.notificationTitle,
                body: notificationBody,
                threadIdentifier: callPreview?.threadIdentifier,
                userInfo: userInfo,
                soundQuery: .thread(threadUniqueId),
                replacingIdentifier: notificationInfo.groupingId.uuidString,
            )
        }
    }

    public func notifyUserOfMissedCallBecauseOfNewIdentity(
        notificationInfo: CallNotificationInfo,
        tx: DBWriteTransaction,
    ) {
        let thread = notificationInfo.thread
        let callPreview = fetchCallPreview(thread: .individualThread(thread), tx: tx)

        let notificationBody = NotificationStrings.missedCallBecauseOfIdentityChangeBody
        let userInfo = userInfoForMissedCall(thread: thread, remoteAci: notificationInfo.caller)

        let category: AppNotificationCategory = (
            callPreview?.shouldShowActions == true
                ? .missedCallWithActions
                : .missedCallWithoutActions,
        )

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction(afterCommitting: tx) {
            await self.notifyViaPresenter(
                category: category,
                title: callPreview?.notificationTitle,
                body: notificationBody,
                threadIdentifier: callPreview?.threadIdentifier,
                userInfo: userInfo,
                soundQuery: .thread(threadUniqueId),
                replacingIdentifier: notificationInfo.groupingId.uuidString,
            )
        }
    }

    private func userInfoForMissedCall(thread: TSThread, remoteAci: Aci) -> AppNotificationUserInfo {
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = thread.uniqueId
        userInfo.callBackAci = remoteAci
        userInfo.isMissedCall = true
        return userInfo
    }

    // MARK: - Notify

    public func isThreadMuted(_ thread: TSThread, transaction: DBReadTransaction) -> Bool {
        ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction).isMuted
    }

    public func canNotify(
        for incomingMessage: TSIncomingMessage,
        thread: TSThread,
        transaction: DBReadTransaction,
    ) -> Bool {
        if isThreadMuted(thread, transaction: transaction) {
            guard thread.isGroupThread else { return false }

            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction) else {
                owsFailDebug("Missing local address")
                return false
            }

            let mentionedAcis = MentionFinder.mentionedAcis(for: incomingMessage, tx: transaction)
            let localUserIsQuoted = incomingMessage.quotedMessage?.authorAddress.isEqualToAddress(localIdentifiers.aciAddress) ?? false
            guard mentionedAcis.contains(localIdentifiers.aci) || localUserIsQuoted else {
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

            let localAci = tsAccountManager.localIdentifiers(tx: transaction)?.aci

            // Always notify for replies to group stories you sent
            if storyAuthorAci == localAci { return true }

            // Always notify if you have been @mentioned
            if
                let mentionedAcis = incomingMessage.bodyRanges?.mentions.values,
                mentionedAcis.contains(where: { $0 == localAci })
            {
                return true
            }

            // Notify people who did not author the story if they've previously replied to it
            return InteractionFinder.hasLocalUserReplied(
                storyTimestamp: storyTimestamp,
                storyAuthorAci: storyAuthorAci,
                transaction: transaction,
            )
        } else {
            return true
        }
    }

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        _notifyUser(
            forIncomingMessage: incomingMessage,
            editTarget: nil,
            thread: thread,
            transaction: transaction,
        )
    }

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        editTarget: TSIncomingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        _notifyUser(
            forIncomingMessage: incomingMessage,
            editTarget: editTarget,
            thread: thread,
            transaction: transaction,
        )
    }

    public func notifyUserOfPollEnd(
        forMessage message: TSIncomingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        guard let notifiableThread = NotifiableThread(thread) else {
            owsFailDebug("Can't notify for \(type(of: thread))")
            return
        }

        guard !isThreadMuted(thread, transaction: transaction) else { return }

        // Poll terminate notifications only get displayed if we can include the poll details.
        let previewType = self.previewType(tx: transaction)
        guard previewType == .namePreview else {
            return
        }
        owsPrecondition(Self.shouldShowActions(for: previewType))

        let notificationTitle = self.notificationTitle(
            for: notifiableThread,
            senderAddress: message.authorAddress,
            isGroupStoryReply: false,
            previewType: previewType,
            tx: transaction,
        )

        let pollEndedFormat = OWSLocalizedString(
            "POLL_ENDED_NOTIFICATION",
            comment: "Notification that {{contact}} ended a poll with question {{poll question}}",
        )
        guard let pollQuestion = message.body else {
            return
        }

        let pollAuthorName = SSKEnvironment.shared.contactManagerRef.nameForAddress(
            message.authorAddress,
            localUserDisplayMode: .noteToSelf,
            short: false,
            transaction: transaction,
        )

        let notificationBody: String = "\u{1F4CA}" + String(format: pollEndedFormat, pollAuthorName.string, pollQuestion)

        let intent = thread.generateSendMessageIntent(context: .senderAddress(message.authorAddress), transaction: transaction)

        var userInfo = AppNotificationUserInfo()
        let threadUniqueId = thread.uniqueId
        userInfo.threadId = threadUniqueId

        enqueueNotificationAction(afterCommitting: transaction) {
            await self.notifyViaPresenter(
                category: .pollEndNotification,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadUniqueId,
                userInfo: userInfo,
                intent: intent.map { ($0, .incoming) },
                soundQuery: .thread(threadUniqueId),
            )
        }
    }

    public func notifyUserOfPollVote(
        forMessage message: TSOutgoingMessage,
        voteAuthor: Aci,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        guard let notifiableThread = NotifiableThread(thread) else {
            owsFailDebug("Can't notify for \(type(of: thread))")
            return
        }

        guard !isThreadMuted(thread, transaction: transaction) else { return }

        // Poll vote notifications only get displayed if we can include the poll details.
        let previewType = self.previewType(tx: transaction)
        guard previewType == .namePreview else {
            return
        }
        owsPrecondition(Self.shouldShowActions(for: previewType))

        let notificationTitle = self.notificationTitle(
            for: notifiableThread,
            senderAddress: SignalServiceAddress(voteAuthor),
            isGroupStoryReply: false,
            previewType: previewType,
            tx: transaction,
        )

        let pollVotedFormat = OWSLocalizedString(
            "POLL_VOTED_NOTIFICATION",
            comment: "Notification that {{contact}} voted in a poll with question {{poll question}}",
        )
        guard let pollQuestion = message.body else {
            return
        }

        let voteAuthorName = SSKEnvironment.shared.contactManagerRef.nameForAddress(
            SignalServiceAddress(voteAuthor),
            localUserDisplayMode: .noteToSelf,
            short: false,
            transaction: transaction,
        )

        let notificationBody: String = "\u{1F4CA}" + String(format: pollVotedFormat, voteAuthorName.string, pollQuestion)

        var userInfo = AppNotificationUserInfo()
        let threadUniqueId = thread.uniqueId
        userInfo.threadId = threadUniqueId
        userInfo.voteAuthorServiceIdBinary = voteAuthor.serviceIdBinary
        userInfo.messageId = message.uniqueId

        let intent = thread.generateSendMessageIntent(context: .senderAddress(SignalServiceAddress(voteAuthor)), transaction: transaction)

        enqueueNotificationAction(afterCommitting: transaction) {
            if await self.presenter.existingPollVoteNotification(author: voteAuthor.serviceIdBinary, pollId: message.uniqueId) {
                return
            }

            await self.notifyViaPresenter(
                category: .pollVoteNotification,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadUniqueId,
                userInfo: userInfo,
                intent: intent.map { ($0, .incoming) },
                soundQuery: .thread(threadUniqueId),
            )
        }
    }

    private enum NotifiableThread {
        case individualThread(TSContactThread)
        case groupThread(TSGroupThread)

        init?(_ thread: TSThread) {
            switch thread {
            case let thread as TSContactThread:
                self = .individualThread(thread)
            case let thread as TSGroupThread:
                self = .groupThread(thread)
            default:
                return nil
            }
        }

        var rawValue: TSThread {
            switch self {
            case .individualThread(let thread):
                return thread
            case .groupThread(let thread):
                return thread
            }
        }
    }

    private func notificationTitle(
        for thread: NotifiableThread,
        senderAddress: SignalServiceAddress?,
        isGroupStoryReply: Bool,
        previewType: NotificationType,
        tx: DBReadTransaction,
    ) -> ResolvableValue<String>? {
        switch previewType {
        case .noNameNoPreview:
            return nil
        case .nameNoPreview, .namePreview:
            switch thread {
            case .individualThread(let thread):
                owsAssertDebug(senderAddress == nil || senderAddress == thread.contactAddress)
                return resolvableValue(
                    withDisplayNameForAddress: thread.contactAddress,
                    transformedBy: { displayName in displayName.resolvedValue() },
                    tx: tx,
                )
            case .groupThread(let thread):
                let groupName = thread.groupNameOrDefault
                if let senderAddress {
                    let format = (
                        isGroupStoryReply
                            ? NotificationStrings.incomingGroupStoryReplyTitleFormat
                            : NotificationStrings.incomingGroupMessageTitleFormat,
                    )
                    return resolvableValue(
                        withDisplayNameForAddress: senderAddress,
                        transformedBy: { displayName in String(format: format, displayName.resolvedValue(), groupName) },
                        tx: tx,
                    )
                } else {
                    return ResolvableValue(resolvedValue: groupName)
                }
            }
        }
    }

    private func resolvableValue(
        withDisplayNameForAddress address: SignalServiceAddress,
        transformedBy transform: @escaping (DisplayName) -> String,
        tx: DBReadTransaction,
    ) -> ResolvableValue<String> {
        // TODO: Stop using SSKEnvironment.shared once dependencies are injected.
        return ResolvableDisplayNameBuilder(
            displayNameForAddress: address,
            transformedBy: { displayName, _ in return transform(displayName) },
            contactManager: SSKEnvironment.shared.contactManagerRef,
        ).resolvableValue(
            db: SSKEnvironment.shared.databaseStorageRef,
            profileFetcher: SSKEnvironment.shared.profileFetcherRef,
            tx: tx,
        )
    }

    private func _notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        editTarget: TSIncomingMessage?,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        guard let notifiableThread = NotifiableThread(thread) else {
            owsFailDebug("Can't notify for \(type(of: thread))")
            return
        }

        guard canNotify(for: incomingMessage, thread: thread, transaction: transaction) else {
            return
        }

        // While batch processing, some of the necessary changes have not been committed.
        let rawMessageText = incomingMessage.notificationPreviewText(transaction)

        let messageText = rawMessageText.filterStringForDisplay()

        let previewType = self.previewType(tx: transaction)

        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            threadIdentifier = nil
        case .nameNoPreview, .namePreview:
            threadIdentifier = thread.uniqueId
        }

        let notificationTitle = self.notificationTitle(
            for: notifiableThread,
            senderAddress: incomingMessage.authorAddress,
            isGroupStoryReply: incomingMessage.isGroupStoryReply,
            previewType: previewType,
            tx: transaction,
        )

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
            if identityManager.verificationState(for: address, tx: transaction) == .noLongerVerified {
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
                    : .incomingMessageWithActions_CannotReply,
            )
        }
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = thread.uniqueId
        userInfo.messageId = incomingMessage.uniqueId
        userInfo.storyTimestamp = incomingMessage.storyTimestamp?.uint64Value

        var intent: ResolvableValue<INIntent>?
        if previewType != .noNameNoPreview {
            intent = thread.generateSendMessageIntent(context: .incomingMessage(incomingMessage), transaction: transaction)
        }

        let threadUniqueId = thread.uniqueId
        let editTargetUniqueId = editTarget?.uniqueId
        enqueueNotificationAction(afterCommitting: transaction) {
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
                intent: intent.map { ($0, .incoming) },
                soundQuery: (editTargetUniqueId != nil) ? .none : .thread(threadUniqueId),
            )
        }
    }

    public func notifyUser(
        forReaction reaction: OWSReaction,
        onOutgoingMessage message: TSOutgoingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        guard let notifiableThread = NotifiableThread(thread) else {
            owsFailDebug("Can't notify for \(type(of: thread))")
            return
        }

        guard !isThreadMuted(thread, transaction: transaction) else { return }

        // Reaction notifications only get displayed if we can include the reaction
        // details, otherwise we don't disturb the user for a non-message
        let previewType = self.previewType(tx: transaction)
        guard previewType == .namePreview else {
            return
        }
        owsPrecondition(Self.shouldShowActions(for: previewType))

        let notificationTitle = self.notificationTitle(
            for: notifiableThread,
            senderAddress: reaction.reactor,
            isGroupStoryReply: false,
            previewType: previewType,
            tx: transaction,
        )

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
                    tx: transaction,
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
            if identityManager.verificationState(for: address, tx: transaction) == .noLongerVerified {
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
                    : .incomingReactionWithActions_CannotReply,
            )
        }
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = thread.uniqueId
        userInfo.messageId = message.uniqueId
        userInfo.reactionId = reaction.uniqueId

        let intent = thread.generateSendMessageIntent(context: .senderAddress(reaction.reactor), transaction: transaction)

        let threadUniqueId = thread.uniqueId
        enqueueNotificationAction(afterCommitting: transaction) {
            await self.notifyViaPresenter(
                category: category,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadUniqueId,
                userInfo: userInfo,
                intent: intent.map { ($0, .incoming) },
                soundQuery: .thread(threadUniqueId),
            )
        }
    }

    public func notifyUserOfFailedSend(inThread thread: TSThread) {
        guard let notifiableThread = NotifiableThread(thread) else {
            owsFailDebug("Can't notify for \(type(of: thread))")
            return
        }

        let notificationTitle = databaseStorage.read { tx in
            return self.notificationTitle(
                for: notifiableThread,
                senderAddress: nil,
                isGroupStoryReply: false,
                previewType: self.previewType(tx: tx),
                tx: tx,
            )
        }

        let notificationBody = NotificationStrings.failedToSendBody
        let threadId = thread.uniqueId
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = threadId

        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .infoOrErrorMessage,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: nil, // show ungrouped
                userInfo: userInfo,
                soundQuery: .thread(threadId),
            )
        }
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        // External devices should still log the error string.
        Logger.error("Fatal error occurred: \(errorString).")
        guard DebugFlags.testPopulationErrorAlerts else {
            return
        }

        let title = OWSLocalizedString(
            "ERROR_NOTIFICATION_TITLE",
            comment: "Format string for an error alert notification title.",
        )
        let messageFormat = OWSLocalizedString(
            "ERROR_NOTIFICATION_MESSAGE_FORMAT",
            comment: "Format string for an error alert notification message. Embeds {{ error string }}",
        )
        let message = String(format: messageFormat, errorString)

        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .submitDebugLogs

        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .internalError,
                title: ResolvableValue(resolvedValue: title),
                body: message,
                threadIdentifier: nil,
                userInfo: userInfo,
                soundQuery: .global,
                forceBeforeRegistered: true,
            )
        }
    }

    public func notifyForGroupCallSafetyNumberChange(
        callTitle: String,
        threadUniqueId: String?,
        roomId: Data?,
        presentAtJoin: Bool,
    ) {
        let notificationTitle = databaseStorage.read { tx -> ResolvableValue<String>? in
            switch previewType(tx: tx) {
            case .noNameNoPreview:
                return nil
            case .nameNoPreview, .namePreview:
                return ResolvableValue(resolvedValue: callTitle)
            }
        }

        let notificationBody = (
            presentAtJoin
                ? NotificationStrings.groupCallSafetyNumberChangeAtJoinBody
                : NotificationStrings.groupCallSafetyNumberChangeBody,
        )

        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .showCallLobby
        userInfo.threadId = threadUniqueId
        userInfo.roomId = roomId

        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .infoOrErrorMessage,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: nil, // show ungrouped
                userInfo: userInfo,
                soundQuery: threadUniqueId.map({ .thread($0) }) ?? .global,
            )
        }
    }

    public func scheduleNotifyForNewLinkedDevice(deviceLinkTimestamp: Date) {
        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .showLinkedDevices
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .newDeviceLinked,
                title: ResolvableValue(resolvedValue: OWSLocalizedString(
                    "LINKED_DEVICE_NOTIFICATION_TITLE",
                    comment: "Title for system notification when a new device is linked.",
                )),
                body: String(
                    format: OWSLocalizedString(
                        "LINKED_DEVICE_NOTIFICATION_BODY",
                        comment: "Body for system notification when a new device is linked. Embeds {{ time the device was linked }}",
                    ),
                    deviceLinkTimestamp.formatted(date: .omitted, time: .shortened),
                ),
                threadIdentifier: nil,
                userInfo: userInfo,
                soundQuery: .global,
            )
        }
    }

    public func scheduleNotifyForBackupsEnabled(backupsTimestamp: Date) {
        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .showBackupsSettings
        enqueueNotificationAction {
            await self.presenter.cancelPendingNotificationsForBackupsEnabled()

            await self.notifyViaPresenter(
                category: .backupsEnabled,
                title: ResolvableValue(resolvedValue: OWSLocalizedString(
                    "BACKUPS_TURNED_ON_TITLE",
                    comment: "Title for system notification or megaphone when backups is enabled",
                )),
                body: String(
                    format: OWSLocalizedString(
                        "BACKUPS_TURNED_ON_NOTIFICATION_BODY_FORMAT",
                        comment: "Body for system notification or megaphone when backups is enabled. Embeds {{ time backups was enabled }}",
                    ),
                    backupsTimestamp.formatted(date: .omitted, time: .shortened),
                ),
                threadIdentifier: nil,
                userInfo: userInfo,
                soundQuery: .global,
            )
        }
    }

    public func notifyUserOfMediaTierQuotaConsumed() {
        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .showBackupsSettings
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .backupsMediaTierQuotaConsumed,
                title: ResolvableValue(resolvedValue: OWSLocalizedString(
                    "BACKUP_SETTINGS_OUT_OF_STORAGE_SPACE_NOTIFICATION_TITLE",
                    comment: "Title for a notification telling the user they are out of remote storage space.",
                )),
                body: OWSLocalizedString(
                    "BACKUP_SETTINGS_OUT_OF_STORAGE_SPACE_NOTIFICATION_SUBTITLE",
                    comment: "Subtitle for a notification telling the user they are out of remote storage space.",
                ),
                threadIdentifier: nil,
                userInfo: userInfo,
                soundQuery: .global,
            )
        }
    }

    public func notifyUserOfListMediaIntegrityCheckFailure() {
        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .listMediaIntegrityCheck
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .listMediaIntegrityCheckFailure,
                title: ResolvableValue(resolvedValue: OWSLocalizedString(
                    "BACKUPS_MEDIA_UPLOAD_FAILURE_NOTIFICATION_TITLE",
                    comment: "Title for system notification when we detect paid backup media uploads have encountered a problem",
                )),
                body: OWSLocalizedString(
                    "BACKUPS_MEDIA_UPLOAD_FAILURE_NOTIFICATION_BODY",
                    comment: "Body for system notification when we detect paid backup media uploads have encountered a problem",
                ),
                threadIdentifier: nil,
                userInfo: userInfo,
                soundQuery: .global,
            )
        }
    }

    public func notifyUser(
        forErrorMessage errorMessage: TSErrorMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        if errorMessage is OWSRecoverableDecryptionPlaceholder {
            return
        }

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
                transaction: transaction,
            )
        }
    }

    public func notifyUser(
        forTSMessage message: TSMessage,
        thread: TSThread,
        wantsSound: Bool,
        transaction: DBWriteTransaction,
    ) {
        notifyUser(
            tsInteraction: message,
            previewProvider: { tx in
                return message.notificationPreviewText(tx)
            },
            thread: thread,
            wantsSound: wantsSound,
            transaction: transaction,
        )
    }

    public func notifyUser(
        forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
        thread: TSThread,
        wantsSound: Bool,
        transaction: DBWriteTransaction,
    ) {
        notifyUser(
            tsInteraction: previewableInteraction,
            previewProvider: { tx in
                return previewableInteraction.previewText(transaction: tx)
            },
            thread: thread,
            wantsSound: wantsSound,
            transaction: transaction,
        )
    }

    private func notifyUser(
        tsInteraction: TSInteraction,
        previewProvider: (DBWriteTransaction) -> String,
        thread: TSThread,
        wantsSound: Bool,
        transaction: DBWriteTransaction,
    ) {
        guard let notifiableThread = NotifiableThread(thread) else {
            owsFailDebug("Can't notify for \(type(of: thread))")
            return
        }

        guard !isThreadMuted(thread, transaction: transaction) else { return }

        let previewType = self.previewType(tx: transaction)

        let threadIdentifier: String?
        switch previewType {
        case .noNameNoPreview:
            threadIdentifier = nil
        case .namePreview, .nameNoPreview:
            threadIdentifier = thread.uniqueId
        }

        let notificationTitle = self.notificationTitle(
            for: notifiableThread,
            senderAddress: nil,
            isGroupStoryReply: false,
            previewType: previewType,
            tx: transaction,
        )

        let notificationBody: String
        switch previewType {
        case .noNameNoPreview, .nameNoPreview:
            notificationBody = NotificationStrings.genericIncomingMessageNotification
        case .namePreview:
            notificationBody = previewProvider(transaction)
        }

        let threadId = thread.uniqueId

        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = threadId
        userInfo.messageId = tsInteraction.uniqueId

        let isGroupCallMessage = tsInteraction is OWSGroupCallMessage
        userInfo.defaultAction = isGroupCallMessage ? .showCallLobby : .showThread

        // Some types of generic messages (locally generated notifications) have a defacto
        // "sender". If so, generate an interaction so the notification renders as if it
        // is from that user.
        var intent: ResolvableValue<INIntent>?
        if previewType != .noNameNoPreview {
            if let infoMessage = tsInteraction as? TSInfoMessage {
                guard
                    let localIdentifiers = tsAccountManager.localIdentifiers(
                        tx: transaction,
                    )
                else {
                    owsFailDebug("Missing local identifiers!")
                    return
                }
                switch infoMessage.messageType {
                case .typeGroupUpdate:
                    let groupUpdateAuthor: SignalServiceAddress?
                    switch infoMessage.groupUpdateMetadata(localIdentifiers: localIdentifiers) {
                    case .legacyRawString, .nonGroupUpdate:
                        groupUpdateAuthor = nil
                    case .newGroup(_, let source), .modelDiff(_, _, let source):
                        switch source {
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
                    if let groupUpdateAuthor {
                        intent = thread.generateSendMessageIntent(context: .senderAddress(groupUpdateAuthor), transaction: transaction)
                    }
                case .userJoinedSignal:
                    if let thread = thread as? TSContactThread {
                        intent = thread.generateSendMessageIntent(context: .senderAddress(thread.contactAddress), transaction: transaction)
                    }
                default:
                    break
                }
            } else if let callCreator = (tsInteraction as? OWSGroupCallMessage)?.creatorAci?.wrappedAciValue {
                intent = thread.generateSendMessageIntent(context: .senderAddress(SignalServiceAddress(callCreator)), transaction: transaction)
            }
        }

        enqueueNotificationAction(afterCommitting: transaction) {
            await self.notifyViaPresenter(
                category: .infoOrErrorMessage,
                title: notificationTitle,
                body: notificationBody,
                threadIdentifier: threadIdentifier,
                userInfo: userInfo,
                intent: intent.map { ($0, .incoming) },
                soundQuery: wantsSound ? .thread(threadId) : .none,
            )
        }
    }

    public func notifyUser(
        forFailedStorySend storyMessage: StoryMessage,
        to thread: TSThread,
        transaction: DBWriteTransaction,
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
            suggestionType: .none,
        )

        let sendMessageIntent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: storyName),
            conversationIdentifier: conversationIdentifier,
            serviceName: nil,
            sender: person,
            attachments: nil,
        )

        let notificationTitle = storyName
        let notificationBody = OWSLocalizedString(
            "STORY_SEND_FAILED_NOTIFICATION_BODY",
            comment: "Body for notification shown when a story fails to send.",
        )
        let threadIdentifier = thread.uniqueId
        let storyMessageId = storyMessage.uniqueId

        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .showMyStories
        userInfo.storyMessageId = storyMessageId

        enqueueNotificationAction(afterCommitting: transaction) {
            await self.notifyViaPresenter(
                category: .failedStorySend,
                title: ResolvableValue(resolvedValue: notificationTitle),
                body: notificationBody,
                threadIdentifier: threadIdentifier,
                userInfo: userInfo,
                intent: (ResolvableValue(resolvedValue: sendMessageIntent), .outgoing),
                soundQuery: .global,
            )
        }
    }

    public func notifyUserToRelaunchAfterTransfer(completion: @escaping () -> Void) {
        let notificationBody = OWSLocalizedString(
            "TRANSFER_RELAUNCH_NOTIFICATION",
            comment: "Notification prompting the user to relaunch Signal after a device transfer completed.",
        )
        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .showChatList
        enqueueNotificationAction {
            await self.notifyViaPresenter(
                category: .transferRelaunch,
                title: nil,
                body: notificationBody,
                threadIdentifier: nil,
                userInfo: userInfo,
                // Use a default sound so we don't read from
                // the db (which doesn't work until we relaunch)
                soundQuery: .constant(.standard(.note)),
                forceBeforeRegistered: true,
            )
            completion()
        }
    }

    public func notifyUserOfDeregistration(tx: DBWriteTransaction) {
        let notificationBody = OWSLocalizedString(
            "DEREGISTRATION_NOTIFICATION",
            comment: "Notification warning the user that they have been de-registered.",
        )
        var userInfo = AppNotificationUserInfo()
        userInfo.defaultAction = .reregister
        enqueueNotificationAction(afterCommitting: tx) {
            await self.notifyViaPresenter(
                category: .deregistration,
                title: nil,
                body: notificationBody,
                threadIdentifier: nil,
                userInfo: userInfo,
                soundQuery: .global,
                forceBeforeRegistered: true,
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
        title resolvableTitle: ResolvableValue<String>?,
        body: String,
        threadIdentifier: String?,
        userInfo: AppNotificationUserInfo,
        intent intentPair: (resolvableIntent: ResolvableValue<INIntent>, direction: INInteractionDirection)? = nil,
        soundQuery: SoundQuery,
        replacingIdentifier: String? = nil,
        forceBeforeRegistered: Bool = false,
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

        // Fetching these is currently best effort. (This could be improved in the
        // future.)
        let kProfileNameFetchTimeout: TimeInterval = 5

        async let resolvedTitle = resolvableTitle?.resolve(timeout: kProfileNameFetchTimeout)

        let resolvedInteraction: INInteraction?
        if let intentPair {
            let intent = await intentPair.resolvableIntent.resolve(timeout: kProfileNameFetchTimeout)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = intentPair.direction
            resolvedInteraction = interaction
        } else {
            resolvedInteraction = nil
        }

        await self.presenter.notify(
            category: category,
            title: await resolvedTitle,
            body: body,
            threadIdentifier: threadIdentifier,
            userInfo: userInfo,
            interaction: resolvedInteraction,
            sound: sound,
            replacingIdentifier: replacingIdentifier,
            forceBeforeRegistered: forceBeforeRegistered,
            isMainAppAndActive: notificationSuppressionRule != nil,
            notificationSuppressionRule: notificationSuppressionRule ?? .none,
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

    public func clearNotificationsForAppActivate() {
        presenter.clearNotificationsForAppActivate()
    }

    public func clearDeliveredNewLinkedDevicesNotifications() {
        presenter.clearDeliveredNewLinkedDevicesNotifications()
    }

    // MARK: - Serialization

    private static let pendingTasks = PendingTasks()

    public static func waitForPendingNotifications() async throws {
        try await pendingTasks.waitForPendingTasks()
    }

    private let mostRecentTask = AtomicValue<Task<Void, Never>?>(nil, lock: .init())

    private func enqueueNotificationAction(afterCommitting tx: DBReadTransaction? = nil, _ block: @escaping () async -> Void) {
        let startTime = CACurrentMediaTime()
        let pendingTask = Self.pendingTasks.buildPendingTask()
        let commitGuarantee = (tx as? DBWriteTransaction).map {
            let (guarantee, future) = Guarantee<Void>.pending()
            $0.addSyncCompletion { future.resolve() }
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
        let recentThreshold = now - UInt64(kAudioNotificationsThrottleInterval * Double(UInt64.secondInMs))

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

    subscript(position: Index) -> Element {
        return contents[position]
    }

    func index(after i: Index) -> Index {
        return contents.index(after: i)
    }
}
