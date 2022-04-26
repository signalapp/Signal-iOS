import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public final class NotifyPNServerJob : NSObject, Job, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    struct RequestBody: Codable {
        enum CodingKeys: String, CodingKey {
            case data
            case sendTo = "send_to"
        }
        
        let data: String
        let sendTo: String
    }
    
    public let message: SnodeMessage
    public var delegate: JobDelegate?
    public var id: String?
    public var failureCount: UInt = 0

    // MARK: Settings
    public class var collection: String { return "NotifyPNServerJobCollection" }
    public static let maxFailureCount: UInt = 20

    // MARK: Initialization
    init(message: SnodeMessage) {
        self.message = message
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let message = coder.decodeObject(forKey: "message") as! SnodeMessage?,
            let id = coder.decodeObject(forKey: "id") as! String? else { return nil }
        self.message = message
        self.id = id
        self.failureCount = coder.decodeObject(forKey: "failureCount") as! UInt? ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(message, forKey: "message")
        coder.encode(id, forKey: "id")
        coder.encode(failureCount, forKey: "failureCount")
    }

    // MARK: - Running
    
    public func execute() {
        let _: Promise<Void> = execute()
    }
    
    public func execute() -> Promise<Void> {
        if let id = id {
            JobQueue.currentlyExecutingJobs.mutate{ $0.insert(id) }
        }
        let server = PushNotificationAPI.server
        let url = URL(string: "\(server)/notify")!
        let requestBody: RequestBody = RequestBody(data: message.data.description, sendTo: message.recipient)
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [ Header.contentType.rawValue: "application/json" ]
        request.httpBody = body
        
        let promise = attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, using: .v2, with: PushNotificationAPI.serverPublicKey)
                .map { _ in }
        }
        let _ = promise.done(on: DispatchQueue.global()) { // Intentionally capture self
            self.handleSuccess()
        }
        promise.catch(on: DispatchQueue.global()) { error in
            self.handleFailure(error: error)
        }
        return promise
    }

    private func handleSuccess() {
        delegate?.handleJobSucceeded(self)
    }

    private func handleFailure(error: Error) {
        delegate?.handleJobFailed(self, with: error)
    }
}

