import PromiseKit

// Some important notes about YapDatabase:
//
// • Connections are thread-safe.
// • Executing a write transaction from within a write transaction is NOT allowed.

@objc(LKStorage)
public final class Storage : NSObject {
    private static let queue = DispatchQueue(label: "Storage.queue", qos: .userInitiated)

    private static var owsStorage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: Reading

    // Some important points regarding reading from the database:
    //
    // • Background threads should use `OWSPrimaryStorage`'s `dbReadConnection`, whereas the main thread should use `OWSPrimaryStorage`'s `uiDatabaseConnection` (see the `YapDatabaseConnectionPool` documentation for more information).
    // • Multiple read transactions can safely be executed at the same time.

    @objc(readWithBlock:)
    public static func read(with block: @escaping (YapDatabaseReadTransaction) -> Void) {
        let isMainThread = Thread.current.isMainThread
        let connection = isMainThread ? owsStorage.uiDatabaseConnection : owsStorage.dbReadConnection
        connection.read(block)
    }

    // MARK: Writing

    // Some important points regarding writing to the database:
    //
    // • There can only be a single write transaction per database at any one time, so all write transactions must use `OWSPrimaryStorage`'s `dbReadWriteConnection`.
    // • Executing a write transaction from within a write transaction causes a deadlock and must be avoided.

    @objc(writeWithBlock:)
    public static func objc_write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) -> AnyPromise {
        return AnyPromise.from(write(with: block))
    }

    public static func write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        queue.async { // TODO: There are cases where this isn't necessary
            owsStorage.dbReadWriteConnection.readWrite(block)
            seal.fulfill(())
        }
        return promise
    }

    /// Blocks the calling thread until the write has finished.
    @objc(syncWriteWithBlock:error:)
    public static func objc_syncWrite(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) throws {
        try syncWrite(with: block)
    }

    /// Blocks the calling thread until the write has finished.
    public static func syncWrite(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) throws {
        try write(with: block).wait()
    }
}
