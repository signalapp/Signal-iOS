
@objc(SNClosedGroupsV2Migration)
public class ClosedGroupsV2Migration : OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "006"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        let publicKeys = Storage.shared.getUserClosedGroupPublicKeys()
        var keyPairs: [ECKeyPair] = []
        for publicKey in publicKeys {
            guard let privateKey = Storage.shared.getClosedGroupPrivateKey(for: publicKey) else { continue }
            do {
                let keyPair = try ECKeyPair(publicKeyData: Data(hex: publicKey.removing05PrefixIfNeeded()), privateKeyData: Data(hex: privateKey))
                keyPairs.append(keyPair)
            } catch {
                // Do nothing
            }
        }
        Storage.write(with: { transaction in
            for publicKey in publicKeys {
                Storage.shared.addClosedGroupPublicKey(publicKey, using: transaction)
            }
            for keyPair in keyPairs {
                Storage.shared.addClosedGroupEncryptionKeyPair(keyPair, for: keyPair.hexEncodedPublicKey, using: transaction) // In this particular case keyPair.publicKey == groupPublicKey
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion()
        })
    }
}
