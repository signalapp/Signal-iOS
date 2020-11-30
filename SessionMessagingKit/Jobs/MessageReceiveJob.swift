import SessionUtilitiesKit

public final class MessageReceiveJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public let data: Data
    public let openGroupMessageServerID: UInt64?
    public let openGroupID: String?
    public var delegate: JobDelegate?
    public var id: String?
    public var failureCount: UInt = 0

    // MARK: Settings
    public class var collection: String { return "MessageReceiveJobCollection" }
    public static let maxFailureCount: UInt = 10

    // MARK: Initialization
    public init(data: Data, openGroupMessageServerID: UInt64? = nil, openGroupID: String? = nil) {
        self.data = data
        self.openGroupMessageServerID = openGroupMessageServerID
        self.openGroupID = openGroupID
        #if DEBUG
        if openGroupMessageServerID != nil { assert(openGroupID != nil) }
        if openGroupID != nil { assert(openGroupMessageServerID != nil) }
        #endif
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let data = coder.decodeObject(forKey: "data") as! Data?,
            let id = coder.decodeObject(forKey: "id") as! String? else { return nil }
        self.data = data
        self.openGroupMessageServerID = coder.decodeObject(forKey: "openGroupMessageServerID") as! UInt64?
        self.openGroupID = coder.decodeObject(forKey: "openGroupID") as! String?
        self.id = id
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(data, forKey: "data")
        coder.encode(openGroupMessageServerID, forKey: "openGroupMessageServerID")
        coder.encode(openGroupID, forKey: "openGroupID")
        coder.encode(id, forKey: "id")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        Configuration.shared.storage.withAsync({ transaction in // Intentionally capture self
            do {
                let (message, proto) = try MessageReceiver.parse(self.data, openGroupMessageServerID: self.openGroupMessageServerID, using: transaction)
                try MessageReceiver.handle(message, associatedWithProto: proto, openGroupID: self.openGroupID, using: transaction)
                self.handleSuccess()
            } catch {
                SNLog("Couldn't receive message due to error: \(error).")
                if let error = error as? MessageReceiver.Error, !error.isRetryable {
                    self.handlePermanentFailure(error: error)
                } else {
                    self.handleFailure(error: error)
                }
            }
        }, completion: { })
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handlePermanentFailure(error: Error) {
        delegate?.handleJobFailedPermanently(self, with: error)
    }

    private func handleFailure(error: Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

