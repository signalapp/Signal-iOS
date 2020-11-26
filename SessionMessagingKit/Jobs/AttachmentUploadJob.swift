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

        public var errorDescription: String? {
            switch self {
            case .noAttachment: return "No such attachment."
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
        SNLog("Attachment upload failure count: \(failureCount).")
        guard let stream = TSAttachmentStream.fetch(uniqueId: attachmentID) else {
            return handleFailure(error: Error.noAttachment)
        }
        guard !stream.isUploaded else { return handleSuccess() } // Should never occur
        let openGroup = Configuration.shared.storage.getOpenGroup(for: threadID)
        let server = openGroup?.server ?? FileServerAPI.server
        // FIXME: A lot of what's currently happening in FileServerAPI should really be happening here
        FileServerAPI.uploadAttachment(stream, with: attachmentID, to: server).done(on: DispatchQueue.global(qos: .userInitiated)) { // Intentionally capture self
            self.handleSuccess()
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            if let error = error as? Error, case .noAttachment = error {
                self.handlePermanentFailure(error: error)
            } else if let error = error as? DotNetAPI.Error, !error.isRetryable {
                self.handlePermanentFailure(error: error)
            } else {
                self.handleFailure(error: error)
            }
        }
    }

    private func handleSuccess() {
        SNLog("Attachment uploaded successfully.")
        delegate?.handleJobSucceeded(self)
        Configuration.shared.storage.resumeMessageSendJobIfNeeded(messageSendJobID)
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
        let storage = Configuration.shared.storage
        let messageSendJob = storage.getMessageSendJob(for: messageSendJobID)
        storage.withAsync({ transaction in // Intentionally capture self
            MessageSender.handleFailedMessageSend(self.message, with: error, using: transaction)
            if let messageSendJob = messageSendJob {
                storage.markJobAsFailed(messageSendJob, using: transaction)
            }
        }, completion: { })
    }
}

