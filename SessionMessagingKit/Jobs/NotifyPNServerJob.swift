import PromiseKit
import SessionSnodeKit
import SessionUtilities

// TODO: Implementation
// TODO: Result handling
// TODO: Retrying

public final class NotifyPNServerJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    private let message: SnodeMessage
    private var failureCount: UInt

    // MARK: Settings
    private static let maxRetryCount: UInt = 20

    // MARK: Initialization
    init(message: SnodeMessage) {
        self.message = message
        self.failureCount = 0
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let message = coder.decodeObject(forKey: "message") as! SnodeMessage? else { return nil }
        self.message = message
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(message, forKey: "message")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: Running
    public func execute() {
        
    }

    private func handleSuccess() {

    }

    private func handleFailure(error: Error) {
        self.failureCount += 1
    }
}

