
@objc(LKDeviceLinkingSessionDelegate)
public protocol DeviceLinkingSessionDelegate {
    
    @objc func requestUserAuthorization(for deviceLink: DeviceLink)
}
