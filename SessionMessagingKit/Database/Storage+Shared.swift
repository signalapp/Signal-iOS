// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
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
//    @objc public func getUser() -> Legacy.Contact? {
//        return getUser(using: nil)
//    }
//    
//    public func getUser(using transaction: YapDatabaseReadTransaction?) -> Legacy.Contact? {
//        let userPublicKey = getUserHexEncodedPublicKey()
//        var result: Legacy.Contact?
//        
//        if let transaction = transaction {
//            result = Storage.shared.getContact(with: userPublicKey, using: transaction)
//        }
//        else {
//            Storage.read { transaction in
//                result = Storage.shared.getContact(with: userPublicKey, using: transaction)
//            }
//        }
//        return result
//    }
}
