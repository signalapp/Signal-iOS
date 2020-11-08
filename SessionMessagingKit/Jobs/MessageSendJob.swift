import SessionUtilities

// TODO: Destination encoding & decoding
// TODO: Result handling
// TODO: Retrying

public final class MessageSendJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let message: Message
    private let destination: Message.Destination
    public var failureCount: UInt = 0

    // MARK: Settings
    public static let maxFailureCount: UInt = 20

    // MARK: Initialization
    init(message: Message, destination: Message.Destination) {
        self.message = message
        self.destination = destination
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let message = coder.decodeObject(forKey: "message") as! Message?,
            let destination = coder.decodeObject(forKey: "destination") as! Message.Destination? else { return nil }
        self.message = message
        self.destination = destination
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(message, forKey: "message")
        coder.encode(destination, forKey: "destination")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        Configuration.shared.storage.with { transaction in // Intentionally capture self
            Threading.workQueue.async {
                MessageSender.send(self.message, to: self.destination, using: transaction).done(on: Threading.workQueue) {
                    self.handleSuccess()
                }.catch(on: Threading.workQueue) { error in
                    SNLog("Couldn't send message due to error: \(error).")
                    self.handleFailure(error: error)
                }
            }
        }
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Error) {
        self.failureCount += 1
        delegate?.handleJobFailed(self, with: error)
    }
}

