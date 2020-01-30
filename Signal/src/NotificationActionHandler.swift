//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
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
        let uuidString = userInfo[AppNotificationUserInfoKey.callBackUuid] as? String
        let phoneNumber = userInfo[AppNotificationUserInfoKey.callBackPhoneNumber] as? String
        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            throw NotificationError.failDebug("Missing or invalid address.")
        }

        callUIAdapter.startAndShowOutgoingCall(address: address, hasLocalVideo: false)
        return Promise.value(())
    }

    func declineCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw NotificationError.failDebug("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw NotificationError.failDebug("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        callUIAdapter.localHangupCall(localId: localCallId)
        return Promise.value(())
    }

    private func threadWithSneakyTransaction(threadId: String) -> TSThread? {
        return databaseStorage.read { transaction in
            return TSThread.anyFetch(uniqueId: threadId, transaction: transaction)
        }
    }

    func markAsRead(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread = threadWithSneakyTransaction(threadId: threadId) else {
            throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
        }

        return markAsRead(thread: thread)
    }

    func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        guard let thread = threadWithSneakyTransaction(threadId: threadId) else {
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
        if (UIApplication.shared.applicationState == .active) {
            signalApp.presentConversationAndScrollToFirstUnreadMessage(forThreadId: threadId, animated: true)
        } else {
            // On iOS 13, there is a bug with UISplitViewController that causes the `isCollapsed` state to
            // get out of sync while the app isn't active. This results in conversations opening up in the
            // wrong pane when you were in portrait and then try and open the app in landscape. This is
            // a gross hack of a workaround and results in the user seeing the transition between conversations
            // on iOS 13.
            if #available(iOS 14, *) { owsFailDebug("check if this is still broken") }

            if #available(iOS 13, *) {
                DispatchQueue.main.async {
                    self.signalApp.presentConversationAndScrollToFirstUnreadMessage(forThreadId: threadId, animated: true)
                }
            } else {
                signalApp.presentConversationAndScrollToFirstUnreadMessage(forThreadId: threadId, animated: false)
            }
        }
        return Promise.value(())
    }

    private func markAsRead(thread: TSThread) -> Promise<Void> {
        return databaseStorage.write(.promise) { transaction in
            thread.markAllAsRead(with: transaction)
        }
    }
}

extension ThreadUtil {
    static var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    class func sendMessageNonDurably(text: String, thread: TSThread, quotedReplyModel: OWSQuotedReplyModel?, messageSender: MessageSender) -> Promise<Void> {
        return Promise { resolver in
            self.databaseStorage.read { transaction in
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
