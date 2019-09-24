
@objc protocol DeviceLinkingModalDelegate {
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink)
}

extension DeviceLinkingModalDelegate {
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) { /* Do nothing */ } 
}
