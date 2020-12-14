
extension Storage {
    
    static func reset() {
        let userDefaults = UserDefaults.standard
        if userDefaults[.isUsingFullAPNs], let hexEncodedToken = userDefaults[.deviceToken] {
            let token = Data(hex: hexEncodedToken)
            PushNotificationAPI.unregister(token).retainUntilComplete() // TODO: Wait for this to complete?
        }
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.stopPoller()
        appDelegate.stopClosedGroupPoller()
        appDelegate.stopOpenGroupPollers()
        
        OWSStorage.resetAllStorage()
        OWSUserProfile.resetProfileStorage()
        Environment.shared.preferences.clear()
        AppEnvironment.shared.notificationPresenter.clearAllNotifications()
        
        exit(0)
    }
}
