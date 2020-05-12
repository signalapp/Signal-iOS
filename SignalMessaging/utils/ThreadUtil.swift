//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension ThreadUtil {

    private class var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: -

    @discardableResult
    class func enqueueMessage(withContactShare contactShare: OWSContact,
                              thread: TSThread) -> TSOutgoingMessage {
        AssertIsOnMainThread()
        assert(contactShare.ows_isValid())

        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.contactShare = contactShare

        return enqueueMessage(outgoingMessageBuilder: builder, thread: thread)
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread) -> TSOutgoingMessage {

        // PAYMENTS TODO: Is there any reason for this to be main-thread only?

        let dmConfiguration = databaseStorage.read { transaction in
            return thread.disappearingMessagesConfiguration(with: transaction)
        }
        builder.expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

        let message = builder.build()

        databaseStorage.asyncWrite { transaction in
            message.anyInsert(transaction: transaction)
            self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        }

        return message
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread,
                              transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {

        // PAYMENTS TODO: Is there any reason for this to be main-thread only?

        let dmConfiguration = thread.disappearingMessagesConfiguration(with: transaction)
        builder.expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

        let message = builder.build()
        message.anyInsert(transaction: transaction)
        self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

        return message
    }

    // MARK: -

    class func sendMessageNonDurably(message: TSOutgoingMessage) {
        messageSender.sendMessage(message.asPreparer,
                                  success: {
                                    Logger.info("Successfully sent message.")
        },
                                  failure: { error in
                                    owsFailDebug("Failed to send message with error: \(error)")
        })
    }

    // Used by SAE, otherwise we should use the durable `enqueue` counterpart
    @discardableResult
    class func sendMessageNonDurably(contactShare: OWSContact,
                                     thread: TSThread,
                                     completion: @escaping (Error?) -> Void) -> TSOutgoingMessage {
        assert(contactShare.ows_isValid())

        let message: TSOutgoingMessage = databaseStorage.write { transaction in
            let dmConfiguration = thread.disappearingMessagesConfiguration(with: transaction)
            let expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

            let builder = TSOutgoingMessageBuilder(thread: thread)
            builder.expiresInSeconds = expiresInSeconds
            builder.contactShare = contactShare
            let message = builder.build()
            message.anyInsert(transaction: transaction)
            return message
        }

        messageSender.sendMessage(message.asPreparer,
                                  success: {
                                    Logger.debug("Successfully sent contact share.")
                                    DispatchQueue.main.async {
                                        completion(nil)
                                    }
        },
                                  failure: { error in
                                    Logger.error("Failed to send contact share with error: \(error)")
                                    DispatchQueue.main.async {
                                        completion(error)
                                    }
        })

        return message
    }
}
