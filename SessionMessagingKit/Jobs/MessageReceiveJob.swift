import SessionUtilitiesKit

public final class MessageReceiveJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let data: Data
    public var id: String?
    private let messageServerID: UInt64?
    public var failureCount: UInt = 0

    // MARK: Settings
    public class var collection: String { return "MessageReceiveJobCollection" }
    public static let maxFailureCount: UInt = 10

    // MARK: Initialization
    public init(data: Data, messageServerID: UInt64? = nil) {
        self.data = data
        self.messageServerID = messageServerID
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let data = coder.decodeObject(forKey: "data") as! Data?,
            let id = coder.decodeObject(forKey: "id") as! String? else { return nil }
        self.data = data
        self.id = id
        self.messageServerID = coder.decodeObject(forKey: "messageServerUD") as! UInt64?
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(data, forKey: "data")
        coder.encode(id, forKey: "id")
        coder.encode(messageServerID, forKey: "messageServerID")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        Configuration.shared.storage.withAsync({ transaction in // Intentionally capture self
            Threading.workQueue.async {
                do {
                    let (message, proto) = try MessageReceiver.parse(self.data, messageServerID: self.messageServerID, using: transaction)
                    try MessageReceiver.handle(message, associatedWithProto: proto, using: transaction)
                    self.handleSuccess()
                } catch {
                    SNLog("Couldn't parse message due to error: \(error).")
                    if let error = error as? MessageReceiver.Error, !error.isRetryable {
                        self.handlePermanentFailure(error: error)
                    } else {
                        self.handleFailure(error: error)
                    }
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

