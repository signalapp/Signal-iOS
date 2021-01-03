import PromiseKit
import YapDatabase

// Some important notes about YapDatabase:
//
// • Connections are thread-safe.
// • Executing a write transaction from within a write transaction is NOT allowed.

@objc(LKStorage)
public final class Storage : NSObject {
    public static let serialQueue = DispatchQueue(label: "Storage.serialQueue", qos: .userInitiated)

    private static var owsStorage: OWSPrimaryStorageProtocol { SNUtilitiesKitConfiguration.shared.owsPrimaryStorage }
    
    @objc public static let shared = Storage()

    // MARK: Reading

    // Some important points regarding reading from the database:
    //
    // • Background threads should use `OWSPrimaryStorage`'s `dbReadConnection`, whereas the main thread should use `OWSPrimaryStorage`'s `uiDatabaseConnection` (see the `YapDatabaseConnectionPool` documentation for more information).
    // • Multiple read transactions can safely be executed at the same time.

    @objc(readWithBlock:)
    public static func read(with block: @escaping (YapDatabaseReadTransaction) -> Void) {
        owsStorage.dbReadConnection.read(block)
    }

    // MARK: Writing

    // Some important points regarding writing to the database:
    //
    // • There can only be a single write transaction per database at any one time, so all write transactions must use `OWSPrimaryStorage`'s `dbReadWriteConnection`.
    // • Executing a write transaction from within a write transaction causes a deadlock and must be avoided.

    @discardableResult
    @objc(writeWithBlock:)
    public static func objc_write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) -> AnyPromise {
        return AnyPromise.from(write(with: block) { })
    }

    @discardableResult
    public static func write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) -> Promise<Void> {
        return write(with: block) { }
    }

    @discardableResult
    @objc(writeWithBlock:completion:)
    public static func objc_write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void, completion: @escaping () -> Void) -> AnyPromise {
        return AnyPromise.from(write(with: block, completion: completion))
    }

    @discardableResult
    public static func write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void, completion: @escaping () -> Void) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        serialQueue.async {
            owsStorage.dbReadWriteConnection.readWrite { transaction in
                transaction.addCompletionQueue(DispatchQueue.main, completionBlock: completion)
                block(transaction)
            }
            seal.fulfill(())
        }
        return promise
    }

    /// Blocks the calling thread until the write has finished.
    @objc(writeSyncWithBlock:)
    public static func writeSync(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        try! write(with: block, completion: { }).wait() // The promise returned by write(with:completion:) never rejects
    }
}
