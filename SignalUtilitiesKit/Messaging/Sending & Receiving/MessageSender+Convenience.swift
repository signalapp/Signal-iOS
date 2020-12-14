import SessionProtocolKit
import PromiseKit

extension MessageSender {

    // MARK: Durable
    @objc(send:withAttachments:inThread:usingTransaction:)
    public static func send(_ message: VisibleMessage, with attachments: [SignalAttachment], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        prep(attachments, for: message, using: transaction)
        send(message, in: thread, using: transaction)
    }
    
    @objc(send:inThread:usingTransaction:)
    public static func send(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread)
        let job = MessageSendJob(message: message, destination: destination)
        JobQueue.shared.add(job, using: transaction)
        guard let userPublicKey = SNMessagingKitConfiguration.shared.storage.getUserPublicKey() else { return }
        if case .contact(let recipientPublicKey) = destination, message is VisibleMessage, recipientPublicKey != userPublicKey {
            DispatchQueue.main.async {
                // Not strictly true, but nicer from a UX perspective
                NotificationCenter.default.post(name: .encryptingMessage, object: NSNumber(value: message.sentTimestamp!))
            }
        }
    }

    // MARK: Non-Durable
    @objc(sendNonDurably:withAttachments:inThread:usingTransaction:)
    public static func objc_sendNonDurably(_ message: VisibleMessage, with attachments: [SignalAttachment], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(sendNonDurably(message, with: attachments, in: thread, using: transaction))
    }
    
    @objc(sendNonDurably:withAttachmentIDs:inThread:usingTransaction:)
    public static func objc_sendNonDurably(_ message: VisibleMessage, with attachmentIDs: [String], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(sendNonDurably(message, with: attachmentIDs, in: thread, using: transaction))
    }
    
    @objc(sendNonDurably:inThread:usingTransaction:)
    public static func objc_sendNonDurably(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(sendNonDurably(message, in: thread, using: transaction))
    }
    
    public static func sendNonDurably(_ message: VisibleMessage, with attachments: [SignalAttachment], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        prep(attachments, for: message, using: transaction)
        return sendNonDurably(message, with: message.attachmentIDs, in: thread, using: transaction)
    }
    
    public static func sendNonDurably(_ message: VisibleMessage, with attachmentIDs: [String], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        let attachments = attachmentIDs.compactMap { TSAttachmentStream.fetch(uniqueId: $0, transaction: transaction) }
        let attachmentsToUpload = attachments.filter { !$0.isUploaded }
        let attachmentUploadPromises: [Promise<Void>] = attachmentsToUpload.map { stream in
            let openGroup = SNMessagingKitConfiguration.shared.storage.getOpenGroup(for: thread.uniqueId!)
            let server = openGroup?.server ?? FileServerAPI.server
            // FIXME: This is largely a duplication of the code in AttachmentUploadJob
            let maxRetryCount: UInt = (openGroup != nil) ? 24 : 8
            return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .userInitiated)) {
                FileServerAPI.uploadAttachment(stream, with: stream.uniqueId!, to: server)
            }
        }
        return when(resolved: attachmentUploadPromises).then(on: DispatchQueue.global(qos: .userInitiated)) { results -> Promise<Void> in
            let errors = results.compactMap { result -> Swift.Error? in
                if case .rejected(let error) = result { return error } else { return nil }
            }
            if let error = errors.first { return Promise(error: error) }
            return sendNonDurably(message, in: thread, using: transaction)
        }
    }

    public static func sendNonDurably(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread)
        return MessageSender.send(message, to: destination, using: transaction)
    }
}
