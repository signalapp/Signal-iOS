import PromiseKit
import Sodium

extension Storage {

    @discardableResult
    public func write(with block: @escaping (Any) -> Void) -> Promise<Void> {
        Storage.write(with: { block($0) })
    }
    
    @discardableResult
    public func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void> {
        Storage.write(with: { block($0) }, completion: completion)
    }
    
    public func writeSync(with block: @escaping (Any) -> Void) {
        Storage.writeSync { block($0) }
    }

    @objc public func getUser() -> Contact? {
        return getUser(using: nil)
    }
    
    public func getUser(using transaction: YapDatabaseReadTransaction?) -> Contact? {
        let userPublicKey = getUserHexEncodedPublicKey()
        var result: Contact?
        
        if let transaction = transaction {
            result = Storage.shared.getContact(with: userPublicKey, using: transaction)
        }
        else {
            Storage.read { transaction in
                result = Storage.shared.getContact(with: userPublicKey, using: transaction)
            }
        }
        return result
    }
}
