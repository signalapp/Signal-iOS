import SessionUtilities

public final class MessageReceiveJob : NSObject, Job,  NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let data: Data
    public var failureCount: UInt = 0

    // MARK: Settings
    public static let maxFailureCount: UInt = 10

    // MARK: Initialization
    init(data: Data) {
        self.data = data
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let data = coder.decodeObject(forKey: "data") as! Data? else { return nil }
        self.data = data
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(data, forKey: "data")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        Configuration.shared.storage.with { transaction in // Intentionally capture self
            Threading.workQueue.async {
                do {
                    let _ = try MessageReceiver.parse(self.data)
                    self.handleSuccess()
                } catch {
                    SNLog("Couldn't parse message due to error: \(error).")
                    self.handleFailure(error: error)
                }
            }
        }
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

