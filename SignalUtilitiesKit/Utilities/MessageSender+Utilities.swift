import PromiseKit

public extension MessageSender {

    @objc(send:inThread:usingTransaction:)
    static func send(_ message: Message, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
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
