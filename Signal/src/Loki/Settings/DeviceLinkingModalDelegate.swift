
@objc(LKDeviceLinkingModalDelegate)
protocol DeviceLinkingModalDelegate {
    
    /// Provides an opportunity for the slave device to update its UI after the master device has authorized the device linking request.
    func handleDeviceLinkingRequestAuthorized()
}
