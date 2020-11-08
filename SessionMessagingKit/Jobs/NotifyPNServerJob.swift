import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public final class NotifyPNServerJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var delegate: JobDelegate?
    private let message: SnodeMessage
    public var failureCount: UInt = 0

    // MARK: Settings
    public static let maxFailureCount: UInt = 20

    // MARK: Initialization
    init(message: SnodeMessage) {
        self.message = message
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
        let server = Configuration.shared.pnServerURL
        let parameters = [ "data" : message.data.description, "send_to" : message.recipient ]
        let url = URL(string: "\(server)/notify")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, using: Configuration.shared.pnServerPublicKey).map { _ in }
        }.done(on: DispatchQueue.global()) { // Intentionally capture self
            self.handleSuccess()
        }.catch(on: DispatchQueue.global()) { error in
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

