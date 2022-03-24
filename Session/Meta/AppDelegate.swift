import PromiseKit

extension AppDelegate {

    @objc(syncConfigurationIfNeeded)
    func syncConfigurationIfNeeded() {
        guard Storage.shared.getUser()?.name != nil else { return }
        let userDefaults = UserDefaults.standard
        let lastSync = userDefaults[.lastConfigurationSync] ?? .distantPast
        guard Date().timeIntervalSince(lastSync) > 7 * 24 * 60 * 60 else { return } // Sync every 2 days
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        Storage.write { transaction in
            guard let configurationMessage = ConfigurationMessage.getCurrent(with: transaction) else { return }
            
            let job = MessageSendJob(message: configurationMessage, destination: destination)
            JobQueue.shared.add(job, using: transaction)
        }
        
        // Only update the 'lastConfigurationSync' timestamp if we have done the first sync (Don't want
        // a new device config sync to override config syncs from other devices)
        if userDefaults[.hasSyncedInitialConfiguration] {
            userDefaults[.lastConfigurationSync] = Date()
        }
    }

    func forceSyncConfigurationNowIfNeeded() -> Promise<Void> {
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        let (promise, seal) = Promise<Void>.pending()
        
        // Note: SQLite only supports a single write thread so we can be sure this will retrieve the most up-to-date data
        Storage.writeSync { transaction in
            guard Storage.shared.getUser(using: transaction)?.name != nil, let configurationMessage = ConfigurationMessage.getCurrent(with: transaction) else {
                seal.fulfill(())
                return
            }
            
            MessageSender.send(configurationMessage, to: destination, using: transaction).done {
                seal.fulfill(())
            }.catch { _ in
                seal.fulfill(()) // Fulfill even if this failed; the configuration in the swarm should be at most 2 days old
            }.retainUntilComplete()
        }
        return promise
    }

    @objc func startClosedGroupPoller() {
        guard OWSIdentityManager.shared().identityKeyPair() != nil else { return }
        ClosedGroupPoller.shared.start()
    }

    @objc func stopClosedGroupPoller() {
        ClosedGroupPoller.shared.stop()
    }
}
