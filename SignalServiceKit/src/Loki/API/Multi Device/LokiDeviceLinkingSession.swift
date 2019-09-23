import PromiseKit

@objc (LKDeviceLinkingSession)
public final class LokiDeviceLinkingSession : NSObject {
    private let delegate: LokiDeviceLinkingSessionDelegate
    @objc public var isListeningForLinkingRequests = false
    
    // MARK: Lifecycle
    @objc public init(delegate: LokiDeviceLinkingSessionDelegate) {
        self.delegate = delegate
    }

    // MARK: Public API
    @objc public func startListeningForLinkingRequests() {
        isListeningForLinkingRequests = true
    }
    
    @objc public func processLinkingRequest(from slaveHexEncodedPublicKey: String, with slaveSignature: Data) {
        guard isListeningForLinkingRequests else { return }
        stopListeningForLinkingRequests()
        let master = LokiDeviceLink.Device(hexEncodedPublicKey: OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey)
        let slave = LokiDeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = LokiDeviceLink(between: master, and: slave)
        guard isValid(deviceLink) else { return }
        delegate.requestUserAuthorization(for: deviceLink)
    }
    
    @objc public func stopListeningForLinkingRequests() {
        isListeningForLinkingRequests = false
    }
    
    @objc public func authorizeDeviceLink(_ deviceLink: LokiDeviceLink) {
        // TODO: Send a device link authorized message
    }
    
    // MARK: Private API
    private func isValid(_ deviceLink: LokiDeviceLink) -> Bool {
        return true // TODO: Implement
    }
}
