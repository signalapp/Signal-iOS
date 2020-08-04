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

    func markAsRead(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }
        guard let messageId = userInfo[AppNotificationUserInfoKey.messageId] as? String else {
            throw NotificationError.failDebug("messageId was unexpectedly nil")
        }

        return self.databaseStorage.write(.promise) { transaction in
            guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
            }
            guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                throw NotificationError.failDebug("unable to find interaction with id: \(messageId)")
            }
            self.markMessageAsUnread(thread: thread,
                                     interaction: interaction,
                                     transaction: transaction)
        }
    }

    func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }
        guard let messageId = userInfo[AppNotificationUserInfoKey.messageId] as? String else {
            throw NotificationError.failDebug("messageId was unexpectedly nil")
        }

        let (promise, resolver) = Promise<Void>.pending()
        firstly(on: .global()) { () -> Promise<Void> in
            try self.databaseStorage.write { transaction in
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
                }
                guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                    throw NotificationError.failDebug("unable to find interaction with id: \(messageId)")
                }
                guard nil != interaction as? TSIncomingMessage else {
                    throw NotificationError.failDebug("Unexpected interaction type.")
                }
                self.markMessageAsUnread(thread: thread,
                                         interaction: interaction,
                                         transaction: transaction)

                return firstly(on: .global()) {
                    ThreadUtil.sendMessageNonDurably(body: MessageBody(text: replyText, ranges: .empty),
                                                     thread: thread,
                                                     transaction: transaction)
                }.recover(on: .global()) { error -> Promise<Void> in
                    Logger.warn("Failed to send reply message from notification with error: \(error)")
                    self.notificationPresenter.notifyForFailedSend(inThread: thread)
                    throw error
                }
            }
        }.done(on: .global()) { _ in
            resolver.fulfill(())
        }.catch(on: .global()) { (error: Error) in
            resolver.reject(error)
        }
        return promise
    }

    func showThread(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }

        // If this happens when the the app is not, visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        signalApp.presentConversationAndScrollToFirstUnreadMessage(
            forThreadId: threadId,
            animated: UIApplication.shared.applicationState == .active
        )
        return Promise.value(())
    }

    func reactWithThumbsUp(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            throw NotificationError.failDebug("threadId was unexpectedly nil")
        }
        guard let messageId = userInfo[AppNotificationUserInfoKey.messageId] as? String else {
            throw NotificationError.failDebug("messageId was unexpectedly nil")
        }

        let (promise, resolver) = Promise<Void>.pending()
        firstly(on: .global()) { () -> Promise<Void> in
            try self.databaseStorage.write { transaction in
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    throw NotificationError.failDebug("unable to find thread with id: \(threadId)")
                }
                guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                    throw NotificationError.failDebug("unable to find interaction with id: \(messageId)")
                }
                guard let incomingMessage = interaction as? TSIncomingMessage else {
                    throw NotificationError.failDebug("Unexpected interaction type.")
                }

                self.markMessageAsUnread(thread: thread,
                                         interaction: interaction,
                                         transaction: transaction)

                return ReactionManager.localUserReacted(to: incomingMessage, emoji: "👍", isRemoving: false, sendNonDurably: true, transaction: transaction)
            }
        }.done(on: .global()) { _ in
            resolver.fulfill(())
        }.catch(on: .global()) { (error: Error) in
            resolver.reject(error)
        }
        return promise
    }

    private func markMessageAsUnread(thread: TSThread,
                                     interaction: TSInteraction,
                                     transaction: SDSAnyWriteTransaction) {
        guard let message = interaction as? OWSReadTracking else {
            owsFailDebug("Invalid message type.")
            return
        }

        let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbWrite)
        let readCircumstance: OWSReadCircumstance = (hasPendingMessageRequest ? .readOnThisDeviceWhilePendingMessageRequest : .readOnThisDevice)
        message.markAsRead(atTimestamp: NSDate.ows_millisecondTimeStamp(), thread: thread, circumstance: readCircumstance, transaction: transaction)
    }
}

extension ThreadUtil {
    static var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    class func sendMessageNonDurably(body: MessageBody, thread: TSThread, quotedReplyModel: OWSQuotedReplyModel?, messageSender: MessageSender) -> Promise<Void> {
        return Promise { resolver in
            self.databaseStorage.read { transaction in
                _ = self.sendMessageNonDurably(with: body,
                                               thread: thread,
                                               quotedReplyModel: quotedReplyModel,
                                               transaction: transaction,
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
