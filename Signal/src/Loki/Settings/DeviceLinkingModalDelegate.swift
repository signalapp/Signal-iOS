
@objc protocol DeviceLinkingModalDelegate {
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink)
    func handleDeviceLinkingModalDismissed()
}

extension DeviceLinkingModalDelegate {
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) { /* Do nothing */ }
    func handleDeviceLinkingModalDismissed() { /* Do nothing */ }
}
