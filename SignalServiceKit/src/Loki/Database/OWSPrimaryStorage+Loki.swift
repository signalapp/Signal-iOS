
extension OWSPrimaryStorage {
    
    private func getCollection(for primaryDevice: String) -> String {
        return "LokiMultiDevice-\(primaryDevice)"
    }
    
    public func getAuthorisation(forSecondaryDevice secondaryDevice: String, with transaction: YapDatabaseReadTransaction) -> LokiPairingAuthorisation? {
        let query = YapDatabaseQuery(string: "WHERE \(PairingAuthorisationsIndex.secondaryDevicePubKey) = ?", parameters: [secondaryDevice])
        let authorisations = PairingAuthorisationsIndex.getPairingAuthorisations(with: query, transaction: transaction)
        
        // This should never be the case
        if (authorisations.count > 1) { owsFailDebug("[Loki][Multidevice] Found multiple authorisations for secondary device: \(secondaryDevice)") }
        
        return authorisations.first
    }
    
    public func createOrUpdatePairingAuthorisation(_ authorisation: LokiPairingAuthorisation, with transaction: YapDatabaseReadWriteTransaction) {
        // iOS makes this easy, we can group all authorizations into the primary device collection
        // Then we associate an authorisation with the secondary device key
        transaction.setObject(authorisation, forKey: authorisation.secondaryDevicePubKey, inCollection: getCollection(for: authorisation.primaryDevicePubKey))
    }
    
    public func getSecondaryDevices(forPrimaryDevice primaryDevice: String, with transaction: YapDatabaseReadTransaction) -> [String] {
        // primary device collection should have secondary devices as its keys
        return transaction.allKeys(inCollection: getCollection(for: primaryDevice))
    }
    
    public func getPrimaryDevice(forSecondaryDevice secondaryDevice: String, with transaction: YapDatabaseReadTransaction) -> String? {
        let authorisation = getAuthorisation(forSecondaryDevice: secondaryDevice, with: transaction)
        return authorisation?.primaryDevicePubKey
    }
}
