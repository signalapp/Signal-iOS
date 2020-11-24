import PromiseKit

public extension MessageSender {

    @objc(send:withAttachments:inThread:usingTransaction:)
    static func send(_ message: Message, with attachments: [SignalAttachment] = [], in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        if let message = message as? VisibleMessage {
            var streams: [TSAttachmentStream] = []
            attachments.forEach {
                let stream = TSAttachmentStream(contentType: $0.mimeType, byteCount: UInt32($0.dataLength), sourceFilename: $0.sourceFilename,
                    caption: $0.captionText, albumMessageId: nil)
                streams.append(stream)
                stream.write($0.dataSource)
                stream.save(with: transaction)
            }
            message.attachmentIDs = streams.map { $0.uniqueId! }
        }
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread)
        let job = MessageSendJob(message: message, destination: destination)
        SessionMessagingKit.JobQueue.shared.add(job, using: transaction)
    }

    @objc(sendNonDurably:inThread:usingTransaction:)
    static func objc_sendNonDurably(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(sendNonDurably(message, in: thread, using: transaction))
    }
    
    static func sendNonDurably(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread)
        return MessageSender.send(message, to: destination, using: transaction)
    }
}
