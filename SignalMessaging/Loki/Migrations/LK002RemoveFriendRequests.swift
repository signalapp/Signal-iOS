
@objc
public class LK002RemoveFriendRequests : OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "002"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        DispatchQueue.global().async {
            try! Storage.writeSync { transaction in
                var interactionIDsToRemove: [String] = []
                transaction.enumerateRows(inCollection: TSInteraction.collection()) { key, object, _, _ in
                    if !(object is TSInteraction) {
                        interactionIDsToRemove.append(key)
                    }
                }
                interactionIDsToRemove.forEach { transaction.removeObject(forKey: $0, inCollection: TSInteraction.collection()) }
                self.save(with: transaction)
            }
            completion()
        }
    }
}
