import Curve25519Kit
import PromiseKit

@objc (LKDeviceLinkingSession)
public final class LokiDeviceLinkingSession : NSObject {
    private let delegate: LokiDeviceLinkingSessionDelegate
    @objc public var isListeningForLinkingRequests = false
    
    // MARK: Lifecycle
    @objc public static var current: LokiDeviceLinkingSession?
    
    private init(delegate: LokiDeviceLinkingSessionDelegate) {
        self.delegate = delegate
    }

    // MARK: Public API
    public static func startListeningForLinkingRequests(with delegate: LokiDeviceLinkingSessionDelegate) -> LokiDeviceLinkingSession {
        let session = LokiDeviceLinkingSession(delegate: delegate)
        session.isListeningForLinkingRequests = true
        LokiDeviceLinkingSession.current = session
        return session
    }
    
    @objc public func processLinkingRequest(from slaveHexEncodedPublicKey: String, with slaveSignature: Data) {
        guard isListeningForLinkingRequests else { return }
        stopListeningForLinkingRequests()
        let master = LokiDeviceLink.Device(hexEncodedPublicKey: OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey)
        let slave = LokiDeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = LokiDeviceLink(between: master, and: slave)
        guard isValidLinkingRequest(deviceLink) else { return }
        delegate.requestUserAuthorization(for: deviceLink)
    }
    
    public func stopListeningForLinkingRequests() {
        LokiDeviceLinkingSession.current = nil
        isListeningForLinkingRequests = false
    }
    
    public func authorizeDeviceLink(_ deviceLink: LokiDeviceLink) {
        // TODO: Send a device link authorized message
    }
    
    // MARK: Private API
    private func isValidLinkingRequest(_ deviceLink: LokiDeviceLink) -> Bool {
        // When requesting a device link, the slave device signs the master device's public key. When authorizing
        // a device link, the master device signs the slave device's public key.
        let slaveSignature = deviceLink.slave.signature!
        let slavePublicKey = Data(hex: deviceLink.slave.hexEncodedPublicKey)
        let masterPublicKey = Data(hex: deviceLink.master.hexEncodedPublicKey)
        return (try? Ed25519.verifySignature(slaveSignature, publicKey: slavePublicKey, data: masterPublicKey)) ?? false
    }
}
