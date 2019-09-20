
public protocol LokiDeviceLinkingSessionDelegate {
    
    func handleDeviceLinkingRequestReceived(with signature: String)
    func handleDeviceLinkingSessionTimeout()
}
