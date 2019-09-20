
public protocol LokiDeviceLinkingSessionDelegate {
    
    func authorizeDeviceLinkIfValid(_ deviceLink: LokiDeviceLink)
    func handleDeviceLinkingSessionTimeout()
}
