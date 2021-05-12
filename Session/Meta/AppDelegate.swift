import PromiseKit

extension AppDelegate {

    @objc(syncConfigurationIfNeeded)
    func syncConfigurationIfNeeded() {
        guard Storage.shared.getUser()?.name != nil else { return }
        let userDefaults = UserDefaults.standard
        let lastSync = userDefaults[.lastConfigurationSync] ?? .distantPast
        guard Date().timeIntervalSince(lastSync) > 7 * 24 * 60 * 60,
            let configurationMessage = ConfigurationMessage.getCurrent() else { return } // Sync every 2 days
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        Storage.shared.write { transaction in
            let job = MessageSendJob(message: configurationMessage, destination: destination)
            JobQueue.shared.add(job, using: transaction)
        }
        userDefaults[.lastConfigurationSync] = Date()
    }

    func forceSyncConfigurationNowIfNeeded() -> Promise<Void> {
        guard Storage.shared.getUser()?.name != nil,
            let configurationMessage = ConfigurationMessage.getCurrent() else { return Promise.value(()) }
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        let (promise, seal) = Promise<Void>.pending()
        Storage.writeSync { transaction in
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
