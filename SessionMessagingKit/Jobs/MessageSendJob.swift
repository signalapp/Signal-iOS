import SessionUtilities

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
            var rawDestination = coder.decodeObject(forKey: "destination") as! String? else { return nil }
        self.message = message
        if rawDestination.removePrefix("contact(") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let publicKey = rawDestination
            destination = .contact(publicKey: publicKey)
        } else if rawDestination.removePrefix("closedGroup") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let groupPublicKey = rawDestination
            destination = .closedGroup(groupPublicKey: groupPublicKey)
        } else if rawDestination.removePrefix("openGroup") {
            guard rawDestination.removeSuffix(")") else { return nil }
            let components = rawDestination.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard components.count == 2, let channel = UInt64(components[0]) else { return nil }
            let server = components[1]
            destination = .openGroup(channel: channel, server: server)
        } else {
            return nil
        }
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(message, forKey: "message")
        switch destination {
        case .contact(let publicKey): coder.encode("contact(\(publicKey))", forKey: "destination")
        case .closedGroup(let groupPublicKey): coder.encode("closedGroup(\(groupPublicKey))", forKey: "destination")
        case .openGroup(let channel, let server): coder.encode("openGroup(\(channel), \(server))")
        }
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
        delegate?.handleJobFailed(self, with: error)
    }
}

// MARK: Convenience
private extension String {

    @discardableResult
    mutating func removePrefix<T : StringProtocol>(_ prefix: T) -> Bool {
        guard hasPrefix(prefix) else { return false }
        removeFirst(prefix.count)
        return true
    }

    @discardableResult
    mutating func removeSuffix<T : StringProtocol>(_ suffix: T) -> Bool {
        guard hasSuffix(suffix) else { return false }
        removeLast(suffix.count)
        return true
    }
}

