import SessionUtilitiesKit

public final class AttachmentUploadJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let attachmentID: String
    private let threadID: String
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
    public init(attachmentID: String, threadID: String) {
        self.attachmentID = attachmentID
        self.threadID = threadID
    }
    
    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String?,
            let threadID = coder.decodeObject(forKey: "threadID") as! String? else { return nil }
        self.attachmentID = attachmentID
        self.threadID = threadID
    }

    public func encode(with coder: NSCoder) {
        coder.encode(attachmentID, forKey: "attachmentID")
        coder.encode(threadID, forKey: "threadID")
    }

    // MARK: Running
    public func execute() {
        guard let stream = TSAttachmentStream.fetch(uniqueId: attachmentID) else {
            return handleFailure(error: Error.noAttachment)
        }
        guard !stream.isUploaded else { return handleSuccess() } // Should never occur
        let openGroup = Configuration.shared.storage.getOpenGroup(for: threadID)
        let server = openGroup?.server ?? FileServerAPI.server
        FileServerAPI.uploadAttachment(stream, with: attachmentID, to: server).done(on: DispatchQueue.global(qos: .userInitiated)) { // Intentionally capture self
            self.handleSuccess()
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            self.handleFailure(error: error)
        }
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

