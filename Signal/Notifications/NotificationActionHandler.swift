//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

public class NotificationActionHandler {

    private static var callService: CallService { AppEnvironment.shared.callService }

    @MainActor
    class func handleNotificationResponse(
        _ response: UNNotificationResponse,
        appReadiness: AppReadinessSetter,
    ) async throws {
        owsAssertDebug(appReadiness.isAppReady)

        let userInfo = AppNotificationUserInfo(response.notification.request.content.userInfo)

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Logger.debug("default action")
            let defaultAction = userInfo.defaultAction ?? .showThread
            if DebugFlags.internalLogging {
                Logger.info("Performing default action: \(defaultAction)")
            }
            switch defaultAction {
            case .showThread:
                try await showThread(userInfo: userInfo)
            case .showMyStories:
                await showMyStories(appReadiness: appReadiness)
            case .showCallLobby:
                showCallLobby(userInfo: userInfo)
            case .submitDebugLogs:
                await submitDebugLogs(supportTag: nil)
            case .reregister:
                await reregister(appReadiness: appReadiness)
            case .showChatList:
                // No need to do anything.
                break
            case .showLinkedDevices:
                showLinkedDevices()
            case .showBackupsSettings:
                showBackupsSettings()
            case .listMediaIntegrityCheck:
                await submitDebugLogs(supportTag: "BackupsMedia")
            }
        case UNNotificationDismissActionIdentifier:
            // TODO - mark as read?
            Logger.debug("dismissed notification")
            return
        default:
            guard let responseAction = AppNotificationAction(rawValue: response.actionIdentifier) else {
                throw OWSAssertionError("unable to find action for actionIdentifier: \(response.actionIdentifier)")
            }
            if DebugFlags.internalLogging {
                Logger.info("Performing action: \(responseAction)")
            }
            switch responseAction {
            case .callBack:
                try await self.callBack(userInfo: userInfo)
            case .markAsRead:
                try await markAsRead(userInfo: userInfo)
            case .reply:
                guard let textInputResponse = response as? UNTextInputNotificationResponse else {
                    throw OWSAssertionError("response had unexpected type: \(response)")
                }
                try await reply(userInfo: userInfo, replyText: textInputResponse.userText)
            case .showThread:
                try await showThread(userInfo: userInfo)
            case .reactWithThumbsUp:
                try await reactWithThumbsUp(userInfo: userInfo)
            }
        }
    }

    // MARK: -

    @MainActor
    private class func callBack(userInfo: AppNotificationUserInfo) async throws {
        let aci = userInfo.callBackAci
        let phoneNumber = userInfo.callBackPhoneNumber
        let address = SignalServiceAddress.legacyAddress(serviceId: aci, phoneNumber: phoneNumber)
        guard address.isValid else {
            throw OWSAssertionError("Missing or invalid address.")
        }
        let thread = TSContactThread.getOrCreateThread(contactAddress: address)

        guard let viewController = UIApplication.shared.frontmostViewController else {
            throw OWSAssertionError("Missing frontmostViewController.")
        }
        let prepareResult: CallStarter.PrepareToStartCallResult
        do throws(CallStarter.PrepareToStartCallError) {
            prepareResult = try await CallStarter.prepareToStartCall(from: viewController, shouldAskForCameraPermission: false)
        } catch {
            CallStarter.showPrepareToStartCallError(error, from: viewController)
            return
        }
        callService.callUIAdapter.startAndShowOutgoingCall(thread: thread, prepareResult: prepareResult, hasLocalVideo: false)
    }

    private class func markAsRead(userInfo: AppNotificationUserInfo) async throws {
        let notificationMessage = try await self.notificationMessage(forUserInfo: userInfo)
        try await self.markMessageAsRead(notificationMessage: notificationMessage)
    }

    private class func reply(userInfo: AppNotificationUserInfo, replyText: String) async throws {
        guard !replyText.isEmpty else { return }

        let notificationMessage = try await self.notificationMessage(forUserInfo: userInfo)
        let thread = notificationMessage.thread
        let interaction = notificationMessage.interaction
        var draftModelForSending: DraftQuotedReplyModel.ForSending?
        guard (interaction is TSOutgoingMessage) || (interaction is TSIncomingMessage) else {
            throw OWSAssertionError("Unexpected interaction type.")
        }

        let optionalDraftModel: DraftQuotedReplyModel? = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            if
                let incomingMessage = notificationMessage.interaction as? TSIncomingMessage,
                let draftQuotedReplyModel = DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(originalMessage: incomingMessage, tx: transaction)
            {
                return draftQuotedReplyModel
            }
            return nil
        }

        if let draftModel = optionalDraftModel {
            draftModelForSending = try? await DependenciesBridge.shared.quotedReplyManager.prepareDraftForSending(draftModel)
        }

        let messageBody = try await DependenciesBridge.shared.attachmentContentValidator
            .prepareOversizeTextIfNeeded(MessageBody(text: replyText, ranges: .empty))

        do {
            try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)
                builder.setMessageBody(messageBody)

                // If we're replying to a group story reply, keep the reply within that context.
                if
                    let incomingMessage = interaction as? TSIncomingMessage,
                    notificationMessage.isGroupStoryReply,
                    let storyTimestamp = incomingMessage.storyTimestamp,
                    let storyAuthorAci = incomingMessage.storyAuthorAci
                {
                    builder.storyTimestamp = storyTimestamp
                    builder.storyAuthorAci = storyAuthorAci
                } else {
                    // We only use the thread's DM timer for normal messages & 1:1 story
                    // replies -- group story replies last for the lifetime of the story.
                    let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)
                    builder.expiresInSeconds = dmConfig.durationSeconds
                    builder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)
                }

                let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
                    TSOutgoingMessage(
                        outgoingMessageWith: builder,
                        additionalRecipients: [],
                        explicitRecipients: [],
                        skippedRecipients: [],
                        transaction: transaction,
                    ),
                    body: messageBody,
                    quotedReplyDraft: draftModelForSending,
                )
                let preparedMessage = try unpreparedMessage.prepare(tx: transaction)
                return ThreadUtil.enqueueMessagePromise(message: preparedMessage, transaction: transaction)
            }.awaitableWithUncooperativeCancellationHandling()
        } catch {
            Logger.warn("Failed to send reply message from notification with error: \(error)")
            SSKEnvironment.shared.notificationPresenterRef.notifyUserOfFailedSend(inThread: thread)
            throw error
        }
        try await self.markMessageAsRead(notificationMessage: notificationMessage)
    }

    @MainActor
    private class func showThread(userInfo: AppNotificationUserInfo) async throws {
        let notificationMessage = try await self.notificationMessage(forUserInfo: userInfo)
        if notificationMessage.isGroupStoryReply {
            self.showGroupStoryReplyThread(notificationMessage: notificationMessage)
        } else {
            self.showThread(uniqueId: notificationMessage.thread.uniqueId)
        }
    }

    @MainActor
    private class func showMyStories(appReadiness: AppReadiness) async {
        await withCheckedContinuation { continuation in
            appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
                continuation.resume()
            }
        }
        SignalApp.shared.showMyStories(animated: UIApplication.shared.applicationState == .active)
    }

    @MainActor
    private class func showThread(uniqueId: String) {
        // If this happens when the app is not visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        SignalApp.shared.presentConversationAndScrollToFirstUnreadMessage(
            threadUniqueId: uniqueId,
            animated: UIApplication.shared.applicationState == .active,
        )
    }

    @MainActor
    private class func showGroupStoryReplyThread(notificationMessage: NotificationMessage) {
        guard notificationMessage.isGroupStoryReply, let storyMessage = notificationMessage.storyMessage else {
            return owsFailDebug("Unexpectedly missing story message")
        }

        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else { return }

        if let replySheet = frontmostViewController as? StoryGroupReplier {
            if replySheet.storyMessage.uniqueId == storyMessage.uniqueId {
                return // we're already in the right place
            } else {
                // we need to drop the viewer before we present the new viewer
                replySheet.presentingViewController?.dismiss(animated: false) {
                    showGroupStoryReplyThread(notificationMessage: notificationMessage)
                }
                return
            }
        } else if let storyPageViewController = frontmostViewController as? StoryPageViewController {
            if storyPageViewController.currentMessage?.uniqueId == storyMessage.uniqueId {
                // we're in the right place, just pop the replies sheet
                storyPageViewController.currentContextViewController.presentRepliesAndViewsSheet()
                return
            } else {
                // we need to drop the viewer before we present the new viewer
                storyPageViewController.dismiss(animated: false) {
                    showGroupStoryReplyThread(notificationMessage: notificationMessage)
                }
                return
            }
        }

        let vc = StoryPageViewController(
            context: storyMessage.context,
            // Fresh state when coming in from a notification; no need to share.
            spoilerState: SpoilerRenderState(),
            loadMessage: storyMessage,
            action: .presentReplies,
        )
        frontmostViewController.present(vc, animated: true)
    }

    private class func reactWithThumbsUp(userInfo: AppNotificationUserInfo) async throws {
        let notificationMessage = try await self.notificationMessage(forUserInfo: userInfo)

        let thread = notificationMessage.thread
        let interaction = notificationMessage.interaction
        guard let incomingMessage = interaction as? TSIncomingMessage else {
            throw OWSAssertionError("Unexpected interaction type.")
        }

        do {
            try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                ReactionManager.localUserReacted(
                    to: incomingMessage.uniqueId,
                    emoji: "👍",
                    isRemoving: false,
                    isHighPriority: false,
                    tx: transaction,
                )
            }.awaitableWithUncooperativeCancellationHandling()
        } catch {
            Logger.warn("Failed to send reply message from notification with error: \(error)")
            SSKEnvironment.shared.notificationPresenterRef.notifyUserOfFailedSend(inThread: thread)
            throw error
        }
        try await self.markMessageAsRead(notificationMessage: notificationMessage)
    }

    @MainActor
    private class func showCallLobby(userInfo: AppNotificationUserInfo) {
        let threadUniqueId = userInfo.threadId
        let callLinkRoomId = userInfo.roomId

        enum LobbyTarget {
            case groupThread(groupId: GroupIdentifier, uniqueId: String)
            case callLink(CallLink)

            var callTarget: CallTarget {
                switch self {
                case .groupThread(let groupId, uniqueId: _):
                    return .groupThread(groupId)
                case .callLink(let callLink):
                    return .callLink(callLink)
                }
            }
        }

        let lobbyTarget = { () -> LobbyTarget? in
            if let threadUniqueId {
                return SSKEnvironment.shared.databaseStorageRef.read { tx in
                    if let groupId = try? (TSThread.anyFetch(uniqueId: threadUniqueId, transaction: tx) as? TSGroupThread)?.groupIdentifier {
                        return .groupThread(groupId: groupId, uniqueId: threadUniqueId)
                    }
                    return nil
                }
            }
            if let callLinkRoomId {
                return SSKEnvironment.shared.databaseStorageRef.read { tx in
                    let callLinkStore = DependenciesBridge.shared.callLinkStore
                    if let callLinkRecord = try? callLinkStore.fetch(roomId: callLinkRoomId, tx: tx) {
                        return .callLink(CallLink(rootKey: callLinkRecord.rootKey))
                    }
                    return nil
                }
            }
            return nil
        }()
        guard let lobbyTarget else {
            owsFailDebug("Couldn't resolve destination for call lobby.")
            return
        }

        let currentCall = Self.callService.callServiceState.currentCall
        if currentCall?.mode.matches(lobbyTarget.callTarget) == true {
            AppEnvironment.shared.windowManagerRef.returnToCallView()
            return
        }

        if currentCall == nil {
            callService.initiateCall(to: lobbyTarget.callTarget, isVideo: true)
            return
        }

        switch lobbyTarget {
        case .groupThread(groupId: _, let uniqueId):
            // If currentCall is non-nil, we can't join a call anyway, so fall back to showing the thread.
            self.showThread(uniqueId: uniqueId)
        case .callLink:
            // Nothing to show for a call link.
            break
        }
    }

    @MainActor
    private class func submitDebugLogs(supportTag: String?) async {
        await withCheckedContinuation { continuation in
            DebugLogs.submitLogs(supportTag: supportTag, dumper: .fromGlobals()) {
                continuation.resume()
            }
        }
    }

    @MainActor
    private class func reregister(appReadiness: AppReadinessSetter) async {
        await withCheckedContinuation { continuation in
            appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
                continuation.resume()
            }
        }
        guard let viewController = CurrentAppContext().frontmostViewController() else {
            Logger.error("Responding to reregister notification action without a view controller!")
            return
        }
        Logger.info("Reregistering from deregistered notification")
        RegistrationUtils.reregister(fromViewController: viewController, appReadiness: appReadiness)
    }

    @MainActor
    private class func showLinkedDevices() {
        SignalApp.shared.showAppSettings(mode: .linkedDevices)
    }

    @MainActor
    private class func showBackupsSettings() {
        SignalApp.shared.showAppSettings(mode: .backups)
    }

    private struct NotificationMessage {
        let thread: TSThread
        let interaction: TSInteraction?
        let storyMessage: StoryMessage?
        let isGroupStoryReply: Bool
        let hasPendingMessageRequest: Bool
    }

    private class func notificationMessage(forUserInfo userInfo: AppNotificationUserInfo) async throws -> NotificationMessage {
        guard let threadId = userInfo.threadId else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }
        let messageId = userInfo.messageId

        return try SSKEnvironment.shared.databaseStorageRef.read { transaction throws -> NotificationMessage in
            guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                throw OWSAssertionError("unable to find thread with id: \(threadId)")
            }

            let interaction: TSInteraction?
            if let messageId {
                interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction)
            } else {
                interaction = nil
            }

            let storyMessage: StoryMessage?
            if
                let message = interaction as? TSMessage,
                let storyTimestamp = message.storyTimestamp?.uint64Value,
                let storyAuthorAci = message.storyAuthorAci
            {
                storyMessage = StoryFinder.story(timestamp: storyTimestamp, author: storyAuthorAci.wrappedAciValue, transaction: transaction)
            } else {
                storyMessage = nil
            }

            let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction)

            return NotificationMessage(
                thread: thread,
                interaction: interaction,
                storyMessage: storyMessage,
                isGroupStoryReply: (interaction as? TSMessage)?.isGroupStoryReply == true,
                hasPendingMessageRequest: hasPendingMessageRequest,
            )
        }
    }

    private class func markMessageAsRead(notificationMessage: NotificationMessage) async throws {
        guard let interaction = notificationMessage.interaction else {
            throw OWSAssertionError("missing interaction")
        }
        return await withCheckedContinuation { continuation in
            SSKEnvironment.shared.receiptManagerRef.markAsReadLocally(
                beforeSortId: interaction.sortId,
                thread: notificationMessage.thread,
                hasPendingMessageRequest: notificationMessage.hasPendingMessageRequest,
                completion: { continuation.resume() },
            )
        }
    }
}
