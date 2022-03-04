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
        let attachments = attachmentIDs.compactMap {
            TSAttachment.fetch(uniqueId: $0, transaction: transaction) as? TSAttachmentStream
        }
        let attachmentsToUpload = attachments.filter { !$0.isUploaded }
        let attachmentUploadPromises: [Promise<UInt64>] = attachmentsToUpload.map { stream in
            let storage = SNMessagingKitConfiguration.shared.storage
            
            if let threadId: String = thread.uniqueId, let openGroup = storage.getOpenGroup(for: threadId) {
                let (promise, seal) = Promise<UInt64>.pending()
                AttachmentUploadJob.upload(
                    stream,
                    using: { data in
                        OpenGroupAPI
                            .uploadFile(
                                data.bytes,
                                to: openGroup.room,
                                on: openGroup.server
                            )
                            .map { _, response -> UInt64 in response.id }
                    },
                    encrypt: false,
                    onSuccess: { fileId in seal.fulfill(fileId) },
                    onFailure: { seal.reject($0) }
                )
                
                return promise
            }
            
            let (promise, seal) = Promise<UInt64>.pending()
            AttachmentUploadJob.upload(
                stream,
                using: FileServerAPIV2.upload,
                encrypt: true,
                onSuccess: { fileId in seal.fulfill(fileId) },
                onFailure: { seal.reject($0) }
            )
            return promise
        }
        
        return when(resolved: attachmentUploadPromises)
            .then(on: DispatchQueue.global(qos: .userInitiated)) { results -> Promise<Void> in
                let errors = results.compactMap { result -> Swift.Error? in
                    if case .rejected(let error) = result { return error } else { return nil }
                }
                if let error = errors.first { return Promise(error: error) }
                let fileIds: [UInt64] = results.compactMap { result -> UInt64? in
                    switch result {
                        case .fulfilled(let fileId): return fileId
                        default: return nil
                    }
                }
                
                return sendNonDurably(message, in: thread, with: fileIds, using: transaction)
            }
    }

    public static func sendNonDurably(_ message: Message, in thread: TSThread, with fileIds: [UInt64]? = nil, using transaction: YapDatabaseReadWriteTransaction) -> Promise<Void> {
        message.threadID = thread.uniqueId!
        let destination = Message.Destination.from(thread, fileIds: fileIds)
        return MessageSender.send(message, to: destination, using: transaction)
    }
    
    public static func sendNonDurably(_ message: VisibleMessage, with attachments: [SignalAttachment], in thread: TSThread) -> Promise<Void> {
        Storage.writeSync { transaction in
            prep(attachments, for: message, using: transaction)
        }
        let attachments = message.attachmentIDs.compactMap { TSAttachment.fetch(uniqueId: $0) as? TSAttachmentStream }
        let attachmentsToUpload = attachments.filter { !$0.isUploaded }
        let attachmentUploadPromises: [Promise<UInt64>] = attachmentsToUpload.map { stream in
            let storage = SNMessagingKitConfiguration.shared.storage
            
            if let openGroup = storage.getOpenGroup(for: thread.uniqueId!) {
                let (promise, seal) = Promise<UInt64>.pending()
                
                AttachmentUploadJob.upload(
                    stream,
                    using: { data in
                        OpenGroupAPI
                            .uploadFile(
                                data.bytes,
                                to: openGroup.room,
                                on: openGroup.server
                            )
                            .map { _, response in response.id }
                    },
                    encrypt: false,
                    onSuccess: { fileId in seal.fulfill(fileId) },
                    onFailure: { seal.reject($0) }
                )
                return promise
            }
            
            let (promise, seal) = Promise<UInt64>.pending()
            AttachmentUploadJob.upload(
                stream,
                using: FileServerAPIV2.upload,
                encrypt: true,
                onSuccess: { fileId in seal.fulfill(fileId) },
                onFailure: { seal.reject($0) }
            )
            
            return promise
        }
        let (promise, seal) = Promise<Void>.pending()
        let results = when(resolved: attachmentUploadPromises).wait()
        let errors = results.compactMap { result -> Swift.Error? in
            if case .rejected(let error) = result { return error } else { return nil }
        }
        if let error = errors.first { seal.reject(error) }
        let fileIds: [UInt64] = results.compactMap { result -> UInt64? in
            switch result {
                case .fulfilled(let fileId): return fileId
                default: return nil
            }
        }
        
        Storage.write { transaction in
            sendNonDurably(message, in: thread, with: fileIds, using: transaction)
                .done {
                    seal.fulfill(())
                }
                .catch { error in
                    seal.reject(error)
                }
        }
        
        return promise
    }
}
