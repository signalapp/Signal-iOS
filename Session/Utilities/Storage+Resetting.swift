import PromiseKit

extension Storage {
    
    static func prepareForV2KeyPairMigration() {
        let userDefaults = UserDefaults.standard
        let isUsingAPNs = userDefaults[.isUsingFullAPNs]
        if isUsingAPNs, let hexEncodedToken = userDefaults[.deviceToken] {
            let token = Data(hex: hexEncodedToken)
            PushNotificationAPI.unregister(token).retainUntilComplete() // TODO: Wait for this to complete?
        }
        let displayName = OWSProfileManager.shared().localProfileName()
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.stopPoller()
        appDelegate.stopClosedGroupPoller()
        appDelegate.stopOpenGroupPollers()
        OWSStorage.resetAllStorage()
        OWSUserProfile.resetProfileStorage()
        Environment.shared.preferences.clear()
        AppEnvironment.shared.notificationPresenter.clearAllNotifications()
        userDefaults[.isUsingFullAPNs] = isUsingAPNs
        userDefaults[.displayName] = displayName
        userDefaults[.isMigratingToV2KeyPair] = true
        exit(0)
    }
    
    static func finishV2KeyPairMigration(navigationController: UINavigationController) {
        let seed = Data.getSecureRandomData(ofSize: 16)!
        let (ed25519KeyPair, x25519KeyPair) = KeyPairUtilities.generate(from: seed)
        KeyPairUtilities.store(seed: seed, ed25519KeyPair: ed25519KeyPair, x25519KeyPair: x25519KeyPair)
        TSAccountManager.sharedInstance().phoneNumberAwaitingVerification = x25519KeyPair.hexEncodedPublicKey
        OWSPrimaryStorage.shared().setRestorationTime(0)
        UserDefaults.standard[.hasViewedSeed] = false
        let displayName = UserDefaults.standard[.displayName]! // Checked earlier
        OWSProfileManager.shared().updateLocalProfileName(displayName, avatarImage: nil, success: { }, failure: { _ in }, requiresSync: false)
        TSAccountManager.sharedInstance().didRegister()
        let homeVC = HomeVC()
        navigationController.setViewControllers([ homeVC ], animated: true)
        let syncTokensJob = SyncPushTokensJob(accountManager: AppEnvironment.shared.accountManager, preferences: Environment.shared.preferences)
        syncTokensJob.uploadOnlyIfStale = false
        let _: Promise<Void> = syncTokensJob.run()
    }
}
