
public protocol LokiDeviceLinkingSessionDelegate {
    
    func requestUserAuthorization(for deviceLink: LokiDeviceLink)
    func handleDeviceLinkingSessionTimeout()
}
