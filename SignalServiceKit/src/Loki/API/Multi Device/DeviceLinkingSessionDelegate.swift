
public protocol DeviceLinkingSessionDelegate {
    
    func requestUserAuthorization(for deviceLink: DeviceLink)
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink)
}
