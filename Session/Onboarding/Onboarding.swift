import Sodium

enum Onboarding {
    
    enum Flow {
        case register, recover, link
        
        func preregister(with seed: Data, ed25519KeyPair: Sign.KeyPair, x25519KeyPair: ECKeyPair) {
            let userDefaults = UserDefaults.standard
            KeyPairUtilities.store(seed: seed, ed25519KeyPair: ed25519KeyPair, x25519KeyPair: x25519KeyPair)
            let x25519PublicKey = x25519KeyPair.hexEncodedPublicKey
            TSAccountManager.sharedInstance().phoneNumberAwaitingVerification = x25519PublicKey
            Storage.writeSync { transaction in
                let user = Contact(sessionID: x25519PublicKey)
                Storage.shared.setContact(user, using: transaction)
            }
            switch self {
            case .register:
                userDefaults[.hasViewedSeed] = false
                // Set hasSyncedInitialConfiguration to true so that when we hit the home screen a configuration sync
                // is triggered (yes, the logic is a bit weird). This is needed so that if the user registers and
                // immediately links a device, there'll be a configuration in their swarm.
                userDefaults[.hasSyncedInitialConfiguration] = true
            case .recover, .link:
                userDefaults[.hasViewedSeed] = true // No need to show it again if the user is restoring or linking
                userDefaults[.hasSyncedInitialConfiguration] = false
            }
            switch self {
            case .register, .recover:
                // Set both lastDisplayNameUpdate and lastProfilePictureUpdate to the current date, so that
                // we don't overwrite what the user set in the display name step with whatever we find in
                // their swarm.
                userDefaults[.lastDisplayNameUpdate] = Date()
                userDefaults[.lastProfilePictureUpdate] = Date()
            case .link: break
            }
        }
    }
}
