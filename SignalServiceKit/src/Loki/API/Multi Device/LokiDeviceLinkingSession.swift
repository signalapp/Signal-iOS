import PromiseKit

@objc(LKDeviceLinkingAPI)
final class LokiDeviceLinkingSession : NSObject {
    private let delegate: LokiDeviceLinkingSessionDelegate
    private var timer: Timer?
    public var isListeningForLinkingRequests = false
    
    // MARK: Lifecycle
    public init(delegate: LokiDeviceLinkingSessionDelegate) {
        self.delegate = delegate
    }
    
    // MARK: Settings
    private let listeningTimeout: TimeInterval = 60

    // MARK: Public API
    public func startListeningForLinkingRequests() {
        isListeningForLinkingRequests = true
        timer = Timer.scheduledTimer(withTimeInterval: listeningTimeout, repeats: false) { [weak self] timer in
            guard let self = self else { return }
            self.stopListeningForLinkingRequests()
            self.delegate.handleDeviceLinkingSessionTimeout()
        }
    }
    
    public func stopListeningForLinkingRequests() {
        timer?.invalidate()
        timer = nil
        isListeningForLinkingRequests = false
    }
    
    public func processLinkingRequest(with signature: String) {
        guard isListeningForLinkingRequests else { return }
        stopListeningForLinkingRequests()
        delegate.handleDeviceLinkingRequestReceived(with: signature)
    }

    public func authorizeLinkingRequest(with signature: String) {
        // TODO: Authorize the linking request with the given signature
    }
}
