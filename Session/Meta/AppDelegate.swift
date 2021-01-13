
extension AppDelegate {

    @objc func syncConfigurationIfNeeded() {
        let userDefaults = UserDefaults.standard
        guard userDefaults[.isUsingMultiDevice] else { return }
        let lastSync = userDefaults[.lastConfigurationSync] ?? .distantPast
        guard Date().timeIntervalSince(lastSync) > 2 * 24 * 60 * 60 else { return } // Sync every 2 days
        let configurationMessage = ConfigurationMessage.getCurrent()
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        Storage.shared.write { transaction in
            let job = MessageSendJob(message: configurationMessage, destination: destination)
            JobQueue.shared.add(job, using: transaction)
        }
    }
}
