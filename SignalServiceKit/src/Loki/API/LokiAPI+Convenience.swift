import PromiseKit

internal extension LokiAPI {

    private static let receivedMessageHashValuesKey = "receivedMessageHashValuesKey"
    private static let receivedMessageHashValuesCollection = "receivedMessageHashValuesCollection"

    internal static func getLastMessageHashValue(for target: Target) -> String? {
        var result: String? = nil
        // Uses a read/write connection because getting the last message hash value also removes expired messages as needed
        storage.dbReadWriteConnection.readWrite { transaction in
            result = storage.getLastMessageHash(forServiceNode: target.address, transaction: transaction)
        }
        return result
    }

    internal static func setLastMessageHashValue(for target: Target, hashValue: String, expiresAt: UInt64) {
        storage.dbReadWriteConnection.readWrite { transaction in
            storage.setLastMessageHash(forServiceNode: target.address, hash: hashValue, expiresAt: expiresAt, transaction: transaction)
        }
    }

    internal static func getReceivedMessageHashValues() -> Set<String>? {
        var result: Set<String>? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: receivedMessageHashValuesKey, inCollection: receivedMessageHashValuesCollection) as! Set<String>?
        }
        return result
    }

    internal static func setReceivedMessageHashValues(to receivedMessageHashValues: Set<String>) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(receivedMessageHashValues, forKey: receivedMessageHashValuesKey, inCollection: receivedMessageHashValuesCollection)
        }
    }
}

internal extension AnyPromise {

    internal static func from<T : Any>(_ promise: Promise<T>) -> AnyPromise {
        let result = AnyPromise(promise)
        result.retainUntilComplete()
        return result
    }
}
