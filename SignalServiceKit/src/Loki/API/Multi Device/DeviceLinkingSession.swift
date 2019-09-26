import Curve25519Kit
import PromiseKit

@objc (LKDeviceLinkingSession)
public final class DeviceLinkingSession : NSObject {
    private let delegate: DeviceLinkingSessionDelegate
    @objc public var isListeningForLinkingRequests = false
    @objc public var isProcessingLinkingRequest = false
    @objc public var isListeningForLinkingAuthorization = false
    
    // MARK: Lifecycle
    @objc public static var current: DeviceLinkingSession?
    
    private init(delegate: DeviceLinkingSessionDelegate) {
        self.delegate = delegate
    }

    // MARK: Public API
    public static func startListeningForLinkingRequests(with delegate: DeviceLinkingSessionDelegate) -> DeviceLinkingSession {
        let session = DeviceLinkingSession(delegate: delegate)
        session.isListeningForLinkingRequests = true
        DeviceLinkingSession.current = session
        return session
    }
    
    public static func startListeningForLinkingAuthorization(with delegate: DeviceLinkingSessionDelegate) -> DeviceLinkingSession {
        let session = DeviceLinkingSession(delegate: delegate)
        session.isListeningForLinkingAuthorization = true
        DeviceLinkingSession.current = session
        return session
    }
    
    @objc public func processLinkingRequest(from slaveHexEncodedPublicKey: String, to masterHexEncodedPublicKey: String, with slaveSignature: Data) {
        guard isListeningForLinkingRequests, !isProcessingLinkingRequest, masterHexEncodedPublicKey == OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey else { return }
        let master = DeviceLink.Device(hexEncodedPublicKey: masterHexEncodedPublicKey)
        let slave = DeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = DeviceLink(between: master, and: slave)
        guard DeviceLinkingUtilities.hasValidSlaveSignature(deviceLink) else { return }
        isProcessingLinkingRequest = true
        DispatchQueue.main.async {
            self.delegate.requestUserAuthorization(for: deviceLink)
        }
    }
    
    @objc public func processLinkingAuthorization(from masterHexEncodedPublicKey: String, for slaveHexEncodedPublicKey: String, masterSignature: Data, slaveSignature: Data) {
        guard isListeningForLinkingAuthorization, slaveHexEncodedPublicKey == OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey else { return }
        let master = DeviceLink.Device(hexEncodedPublicKey: masterHexEncodedPublicKey, signature: masterSignature)
        let slave = DeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = DeviceLink(between: master, and: slave)
        guard DeviceLinkingUtilities.hasValidSlaveSignature(deviceLink) && DeviceLinkingUtilities.hasValidMasterSignature(deviceLink) else { return }
        DispatchQueue.main.async {
            self.delegate.handleDeviceLinkAuthorized(deviceLink)
        }
    }
    
    public func stopListeningForLinkingRequests() {
        DeviceLinkingSession.current = nil
        isListeningForLinkingRequests = false
    }
    
    public func stopListeningForLinkingAuthorization() {
        DeviceLinkingSession.current = nil
        isListeningForLinkingAuthorization = false
    }
    
    public func markLinkingRequestAsProcessed() {
        isProcessingLinkingRequest = false
    }
}
