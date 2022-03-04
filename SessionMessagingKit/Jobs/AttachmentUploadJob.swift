import PromiseKit
import SessionUtilitiesKit

public final class AttachmentUploadJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public let attachmentID: String
    public let threadID: String
    public let message: Message
    public let messageSendJobID: String
    public var delegate: JobDelegate?
    public var id: String?
    public var failureCount: UInt = 0

    public enum Error : LocalizedError {
        case noAttachment
        case encryptionFailed

        public var errorDescription: String? {
            switch self {
            case .noAttachment: return "No such attachment."
            case .encryptionFailed: return "Couldn't encrypt file."
            }
        }
    }
    
    // MARK: Settings
    public class var collection: String { return "AttachmentUploadJobCollection" }
    public static let maxFailureCount: UInt = 20

    // MARK: Initialization
    public init(attachmentID: String, threadID: String, message: Message, messageSendJobID: String) {
        self.attachmentID = attachmentID
        self.threadID = threadID
        self.message = message
        self.messageSendJobID = messageSendJobID
    }
    
    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
            let threadID = coder.decodeObject(forKey: "threadID") as! String?,
            let message = coder.decodeObject(forKey: "message") as! Message?,
            let messageSendJobID = coder.decodeObject(forKey: "messageSendJobID") as! String?,
            let id = coder.decodeObject(forKey: "id") as! String? else { return nil }
        self.attachmentID = attachmentID
        self.threadID = threadID
        self.message = message
        self.messageSendJobID = messageSendJobID
        self.id = id
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(attachmentID, forKey: "attachmentID")
        coder.encode(threadID, forKey: "threadID")
        coder.encode(message, forKey: "message")
        coder.encode(messageSendJobID, forKey: "messageSendJobID")
        coder.encode(id, forKey: "id")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        if let id = id {
            JobQueue.currentlyExecutingJobs.insert(id)
        }
        guard let stream = TSAttachment.fetch(uniqueId: attachmentID) as? TSAttachmentStream else {
            return handleFailure(error: Error.noAttachment)
        }
        guard !stream.isUploaded else { return handleSuccess(stream.serverId) } // Should never occur
        
        let storage = SNMessagingKitConfiguration.shared.storage
        if let openGroup = storage.getOpenGroup(for: threadID) {
            AttachmentUploadJob.upload(
                stream,
                using: { data in
                    OpenGroupAPI.uploadFile(data.bytes, to: openGroup.room, on: openGroup.server)
                        .map { _, response -> UInt64 in response.id }
                },
                encrypt: false,
                onSuccess: { [weak self] fileId in self?.handleSuccess(fileId) },
                onFailure: handleFailure
            )
        }
        else {
            AttachmentUploadJob.upload(
                stream,
                using: FileServerAPIV2.upload,
                encrypt: true,
                onSuccess: { [weak self] fileId in self?.handleSuccess(fileId) },
                onFailure: handleFailure
            )
        }
    }
    
    public static func upload(_ stream: TSAttachmentStream, using upload: (Data) -> Promise<UInt64>, encrypt: Bool, onSuccess: ((UInt64) -> Void)?, onFailure: ((Swift.Error) -> Void)?) {
        // Get the attachment
        guard var data = try? stream.readDataFromFile() else {
            SNLog("Couldn't read attachment from disk.")
            onFailure?(Error.noAttachment); return
        }
        // Encrypt the attachment if needed
        if encrypt {
            var encryptionKey = NSData()
            var digest = NSData()
            guard let ciphertext = Cryptography.encryptAttachmentData(data, shouldPad: true, outKey: &encryptionKey, outDigest: &digest) else {
                SNLog("Couldn't encrypt attachment.")
                onFailure?(Error.encryptionFailed); return
            }
            stream.encryptionKey = encryptionKey as Data
            stream.digest = digest as Data
            data = ciphertext
        }
        // Check the file size
        SNLog("File size: \(data.count) bytes.")
        if Double(data.count) > Double(FileServerAPIV2.maxFileSize) / FileServerAPIV2.fileSizeORMultiplier {
            onFailure?(HTTP.Error.maxFileSizeExceeded)
            return
        }
        
        // Send the request
        stream.isUploaded = false
        stream.save()
        upload(data).done(on: DispatchQueue.global(qos: .userInitiated)) { fileId in
            let downloadURL = "\(FileServerAPIV2.server)/files/\(fileId)"
            stream.serverId = fileId
            stream.isUploaded = true
            stream.downloadURL = downloadURL
            stream.save()
            onSuccess?(fileId)
        }.catch { error in
            onFailure?(error)
        }
    }

    private func handleSuccess(_ fileId: UInt64) {
        SNLog("Attachment uploaded successfully.")
        delegate?.handleJobSucceeded(self)
        
        let messageSendJobId: String = messageSendJobID
        
        Storage.shared.write(
            with: { transaction in
                // Get the existing MessageSendJob and replace it with one that has it's destination updated
                // to include the returned fileId
                if let oldJob: MessageSendJob = SNMessagingKitConfiguration.shared.storage.getMessageSendJob(for: messageSendJobId, using: transaction) {
                    switch oldJob.destination {
                        case .openGroup(let roomToken, let server, let whisperTo, let whisperMods, let oldFileIds):
                            let job: MessageSendJob = MessageSendJob(
                                message: oldJob.message,
                                destination: .openGroup(
                                    roomToken: roomToken,
                                    server: server,
                                    whisperTo: whisperTo,
                                    whisperMods: whisperMods,
                                    fileIds: (oldFileIds ?? []) + [fileId]
                                )
                            )
                            job.id = oldJob.id  // Use the existing id so it gets overwritten
                            job.delegate = oldJob.delegate
                            job.failureCount = oldJob.failureCount
                            
                            // This method just writes the job directly and doesn't generate a new id (as we want)
                            SNMessagingKitConfiguration.shared.storage.persist(job, using: transaction)
                            
                        default: break
                    }
                }
            },
            completion: {
                SNMessagingKitConfiguration.shared.storage.resumeMessageSendJobIfNeeded(messageSendJobId)
                
                Storage.shared.write(with: { transaction in
                    var message: TSMessage?
                    let transaction = transaction as! YapDatabaseReadWriteTransaction
                    TSDatabaseSecondaryIndexes.enumerateMessages(withTimestamp: self.message.sentTimestamp!, with: { _, key, _ in
                        message = TSMessage.fetch(uniqueId: key, transaction: transaction)
                    }, using: transaction)
                    if let message = message {
                        MessageInvalidator.invalidate(message, with: transaction)
                    }
                }, completion: { })
            }
        )
    }
    
    private func handlePermanentFailure(error: Swift.Error) {
        SNLog("Attachment upload failed permanently due to error: \(error).")
        delegate?.handleJobFailedPermanently(self, with: error)
        failAssociatedMessageSendJob(with: error)
    }

    private func handleFailure(error: Swift.Error) {
        SNLog("Attachment upload failed due to error: \(error).")
        delegate?.handleJobFailed(self, with: error)
        if failureCount + 1 == AttachmentUploadJob.maxFailureCount {
            failAssociatedMessageSendJob(with: error)
        }
    }

    private func failAssociatedMessageSendJob(with error: Swift.Error) {
        let storage = SNMessagingKitConfiguration.shared.storage
        let messageSendJob = storage.getMessageSendJob(for: messageSendJobID)
        storage.write(with: { transaction in // Intentionally capture self
            MessageSender.handleFailedMessageSend(self.message, with: error, using: transaction)
            if let messageSendJob = messageSendJob {
                storage.markJobAsFailed(messageSendJob, using: transaction)
            }
        }, completion: { })
    }
}

