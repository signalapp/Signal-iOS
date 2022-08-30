//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class NotificationActionHandler: NSObject {

    @objc
    class func handleNotificationResponse( _ response: UNNotificationResponse, completionHandler: @escaping () -> Void) {
        AssertIsOnMainThread()
        firstly {
            try handleNotificationResponse(response)
        }.done {
            completionHandler()
        }.catch { error in
            owsFailDebug("error: \(error)")
            completionHandler()
        }
    }

    private class func handleNotificationResponse( _ response: UNNotificationResponse) throws -> Promise<Void> {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        let userInfo = response.notification.request.content.userInfo

        let action: AppNotificationAction

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Logger.debug("default action")
            let defaultActionString = userInfo[AppNotificationUserInfoKey.defaultAction] as? String
            let defaultAction = defaultActionString.flatMap { AppNotificationAction(rawValue: $0) }
            action = defaultAction ?? .showThread
        case UNNotificationDismissActionIdentifier:
            // TODO - mark as read?
            Logger.debug("dismissed notification")
            return Promise.value(())
        default:
            if let responseAction = UserNotificationConfig.action(identifier: response.actionIdentifier) {
                action = responseAction
            } else {
                throw OWSAssertionError("unable to find action for actionIdentifier: \(response.actionIdentifier)")
            }
        }

        if DebugFlags.internalLogging {
            Logger.info("Performing action: \(action)")
        }

        switch action {
        case .answerCall:
            return try answerCall(userInfo: userInfo)
        case .callBack:
            return try callBack(userInfo: userInfo)
        case .declineCall:
            return try declineCall(userInfo: userInfo)
        case .markAsRead:
            return try markAsRead(userInfo: userInfo)
        case .reply:
            guard let textInputResponse = response as? UNTextInputNotificationResponse else {
                throw OWSAssertionError("response had unexpected type: \(response)")
            }

            return try reply(userInfo: userInfo, replyText: textInputResponse.userText)
        case .showThread:
            return try showThread(userInfo: userInfo)
        case .reactWithThumbsUp:
            return try reactWithThumbsUp(userInfo: userInfo)
        case .showCallLobby:
            return try showCallLobby(userInfo: userInfo)
        case .submitDebugLogs:
            return submitDebugLogs()
        }
    }

    // MARK: -

    private class func answerCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw OWSAssertionError("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw OWSAssertionError("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        callService.callUIAdapter.answerCall(localId: localCallId)
        return Promise.value(())
    }

    private class func callBack(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        let uuidString = userInfo[AppNotificationUserInfoKey.callBackUuid] as? String
        let phoneNumber = userInfo[AppNotificationUserInfoKey.callBackPhoneNumber] as? String
        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            throw OWSAssertionError("Missing or invalid address.")
        }
        let thread = TSContactThread.getOrCreateThread(contactAddress: address)

        callService.callUIAdapter.startAndShowOutgoingCall(thread: thread, hasLocalVideo: false)
        return Promise.value(())
    }

    private class func declineCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw OWSAssertionError("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw OWSAssertionError("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        callService.callUIAdapter.localHangupCall(localId: localCallId)
        return Promise.value(())
    }

    private class func markAsRead(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly {
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) in
            self.markMessageAsRead(notificationMessage: notificationMessage)
        }
    }

    private class func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) -> Promise<Void> in
            let thread = notificationMessage.thread
            let interaction = notificationMessage.interaction
            guard nil != interaction as? TSIncomingMessage else {
                throw OWSAssertionError("Unexpected interaction type.")
            }

            return firstly(on: .global()) { () -> Promise<Void> in
                self.databaseStorage.write { transaction in
                    let preparer = OutgoingMessagePreparer(
                        messageBody: MessageBody(text: replyText, ranges: .empty),
                        thread: thread,
                        transaction: transaction
                    )
                    preparer.insertMessage(transaction: transaction)
                    return ThreadUtil.enqueueMessagePromise(message: preparer.unpreparedMessage, transaction: transaction)
                }
            }.recover(on: .global()) { error -> Promise<Void> in
                Logger.warn("Failed to send reply message from notification with error: \(error)")
                self.notificationPresenter.notifyForFailedSend(inThread: thread)
                throw error
            }.then(on: .global()) { () -> Promise<Void> in
                self.markMessageAsRead(notificationMessage: notificationMessage)
            }
        }
    }

    private class func showThread(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.done(on: .main) { notificationMessage in
            self.showThread(notificationMessage: notificationMessage)
        }
    }

    private class func showThread(notificationMessage: NotificationMessage) {
        // If this happens when the app is not visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        signalApp.presentConversationAndScrollToFirstUnreadMessage(
            forThreadId: notificationMessage.thread.uniqueId,
            animated: UIApplication.shared.applicationState == .active
        )
    }

    private class func reactWithThumbsUp(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) -> Promise<Void> in
            let thread = notificationMessage.thread
            let interaction = notificationMessage.interaction
            guard let incomingMessage = interaction as? TSIncomingMessage else {
                throw OWSAssertionError("Unexpected interaction type.")
            }

            return firstly(on: .global()) { () -> Promise<Void> in
                self.databaseStorage.write { transaction in
                    ReactionManager.localUserReacted(
                        to: incomingMessage,
                        emoji: "👍",
                        isRemoving: false,
                        isHighPriority: true,
                        transaction: transaction
                    )
                }
            }.recover(on: .global()) { error -> Promise<Void> in
                Logger.warn("Failed to send reply message from notification with error: \(error)")
                self.notificationPresenter.notifyForFailedSend(inThread: thread)
                throw error
            }.then(on: .global()) { () -> Promise<Void> in
                self.markMessageAsRead(notificationMessage: notificationMessage)
            }
        }
    }

    private class func showCallLobby(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.done(on: .main) { notificationMessage in
            let thread = notificationMessage.thread
            let currentCall = Self.callService.currentCall

            if currentCall?.thread.uniqueId == thread.uniqueId {
                OWSWindowManager.shared.returnToCallView()
            } else if let thread = thread as? TSGroupThread, currentCall == nil {
                GroupCallViewController.presentLobby(thread: thread)
            } else {
                // If currentCall is non-nil, we can't join a call anyway, fallback to showing the thread.
                // Individual calls don't have a lobby, just show the thread.
                return self.showThread(notificationMessage: notificationMessage)
            }
        }
    }

    private class func submitDebugLogs() -> Promise<Void> {
        Promise { future in
            Pastelog.submitLogs(withSupportTag: nil) {
                future.resolve()
            }
        }
    }

    private struct NotificationMessage {
        let thread: TSThread
        let interaction: TSInteraction?
        let hasPendingMessageRequest: Bool
    }

    private class func notificationMessage(forUserInfo userInfo: [AnyHashable: Any]) -> Promise<NotificationMessage> {
        firstly(on: .global()) { () throws -> NotificationMessage in
            guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
                throw OWSAssertionError("threadId was unexpectedly nil")
            }
            let messageId = userInfo[AppNotificationUserInfoKey.messageId] as? String

            return try self.databaseStorage.read { (transaction) throws -> NotificationMessage in
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    throw OWSAssertionError("unable to find thread with id: \(threadId)")
                }

                let interaction: TSInteraction?
                if let messageId = messageId {
                    interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction)
                } else {
                    interaction = nil
                }

                let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)

                return NotificationMessage(
                    thread: thread,
                    interaction: interaction,
                    hasPendingMessageRequest: hasPendingMessageRequest
                )
            }
        }
    }

    private class func markMessageAsRead(notificationMessage: NotificationMessage) -> Promise<Void> {
        guard let interaction = notificationMessage.interaction else {
            return Promise(error: OWSAssertionError("missing interaction"))
        }
        let (promise, future) = Promise<Void>.pending()
        self.receiptManager.markAsReadLocally(
            beforeSortId: interaction.sortId,
            thread: notificationMessage.thread,
            hasPendingMessageRequest: notificationMessage.hasPendingMessageRequest
        ) {
            future.resolve()
        }
        return promise
    }
}
