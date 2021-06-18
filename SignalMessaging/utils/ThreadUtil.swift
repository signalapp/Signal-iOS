//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension ThreadUtil {

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

        let dmConfiguration = databaseStorage.read { transaction in
            return thread.disappearingMessagesConfiguration(with: transaction)
        }
        builder.expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

        let message = builder.build()

        databaseStorage.asyncWrite { transaction in
            message.anyInsert(transaction: transaction)
            self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            if message.hasRenderableContent() { thread.donateSendMessageIntent(transaction: transaction) }
        }

        return message
    }

    @discardableResult
    class func enqueueMessage(outgoingMessageBuilder builder: TSOutgoingMessageBuilder,
                              thread: TSThread,
                              transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage {

        let dmConfiguration = thread.disappearingMessagesConfiguration(with: transaction)
        builder.expiresInSeconds = dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0

        let message = builder.build()
        message.anyInsert(transaction: transaction)
        self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

        if message.hasRenderableContent() { thread.donateSendMessageIntent(transaction: transaction) }

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

        if message.hasRenderableContent() { message.threadWithSneakyTransaction?.donateSendMessageIntentWithSneakyTransaction() }
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

        if message.hasRenderableContent() { thread.donateSendMessageIntentWithSneakyTransaction() }

        return message
    }
}

// MARK: -

public extension ThreadUtil {
    class func sendMessageNonDurablyPromise(contactShare: OWSContact,
                                            thread: TSThread) -> Promise<Void> {

        let (promise, resolver) = Promise<Void>.pending()
        ThreadUtil.sendMessageNonDurably(contactShare: contactShare,
                                         thread: thread) { (error: Error?) in
                                            guard let error = error else {
                                                resolver.fulfill(())
                                                return
                                            }
                                            resolver.reject(error)

        }
        return promise
    }

    class func sendMessageNonDurablyPromise(body: MessageBody,
                                            mediaAttachments: [SignalAttachment] = [],
                                            thread: TSThread,
                                            quotedReplyModel: OWSQuotedReplyModel? = nil,
                                            transaction: SDSAnyReadTransaction) -> Promise<Void> {

        let (promise, resolver) = Promise<Void>.pending()
        ThreadUtil.sendMessageNonDurably(body: body,
                                         mediaAttachments: mediaAttachments,
                                         thread: thread,
                                         quotedReplyModel: quotedReplyModel,
                                         linkPreviewDraft: nil,
                                         transaction: transaction) { (error: Error?) in
            guard let error = error else {
                resolver.fulfill(())
                return
            }
            resolver.reject(error)

        }
        return promise
    }

    class func sendMessageNonDurablyPromise(message: TSOutgoingMessage) -> Promise<Void> {
        if message.hasRenderableContent() { message.threadWithSneakyTransaction?.donateSendMessageIntentWithSneakyTransaction() }
        return messageSender.sendMessage(.promise, message.asPreparer)
    }
}

// MARK: - Sharing Suggestions

import Intents

extension TSThread {

    @objc
    public func donateSendMessageIntentWithSneakyTransaction() {
        databaseStorage.read { self.donateSendMessageIntent(transaction: $0) }
    }

    /// This function should be called every time the user
    /// initiates message sending via the UI. It should *not*
    /// be called for messages we send automatically, like
    /// receipts.
    @objc
    public func donateSendMessageIntent(transaction: SDSAnyReadTransaction) {
        // We never need to do this pre-iOS 13, because sharing
        // suggestions aren't support in previous iOS versions.
        guard #available(iOS 13, *) else { return }

        guard SSKPreferences.areSharingSuggestionsEnabled(transaction: transaction) else { return }

        let threadName = contactsManager.displayName(for: self, transaction: transaction)

        let sendMessageIntent = INSendMessageIntent(
            recipients: nil,
            content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: threadName),
            conversationIdentifier: uniqueId,
            serviceName: nil,
            sender: nil
        )

        if let threadAvatar = Self.avatarBuilder.avatarImage(forThread: self,
                                                             diameterPoints: 400,
                                                             localUserDisplayMode: .noteToSelf,
                                                             transaction: transaction),
           let threadAvatarPng = threadAvatar.pngData() {
            let image = INImage(imageData: threadAvatarPng)
            sendMessageIntent.setImage(image, forParameterNamed: \.speakableGroupName)
        }

        let interaction = INInteraction(intent: sendMessageIntent, response: nil)
        interaction.groupIdentifier = uniqueId
        interaction.donate(completion: { error in
            guard let error = error else { return }
            owsFailDebug("Failed to donate message intent for \(self.uniqueId) \(error)")
        })
    }
}
