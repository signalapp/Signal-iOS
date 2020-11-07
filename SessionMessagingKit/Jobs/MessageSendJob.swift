import SessionUtilities

// TODO: Destination encoding & decoding

public final class MessageSendJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    private let message: Message
    private let destination: Message.Destination
    private var failureCount: UInt

    // MARK: Settings
    private static let maxRetryCount: UInt = 20

    // MARK: Initialization
    init(message: Message, destination: Message.Destination) {
        self.message = message
        self.destination = destination
        self.failureCount = 0
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

    }

    private func handleFailure(error: Error) {
        self.failureCount += 1
    }
}

