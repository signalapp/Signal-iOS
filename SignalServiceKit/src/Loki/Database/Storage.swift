
/// Some important notes about YapDatabase:
///
/// • Connections are thread-safe.
/// • Executing a write transaction from within a write transaction is NOT allowed.
@objc(LKStorage)
public final class Storage : NSObject {

    private static var owsStorage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    /// Some important points regarding reading from the database:
    ///
    /// • Background threads should use `OWSPrimaryStorage`'s `dbReadPool`, whereas the main thread should use `OWSPrimaryStorage`'s `uiDatabaseConnection` (see the `YapDatabaseConnectionPool` documentation for more information).
    /// • Multiple read transactions can safely be executed at the same time.
    @objc(readWithBlock:)
    public static func read(with block: @escaping (YapDatabaseReadTransaction) -> Void) {
        let isMainThread = Thread.current.isMainThread
        let connection = isMainThread ? owsStorage.uiDatabaseConnection : owsStorage.dbReadConnection
        connection.read(block)
    }

    /// Some important points regarding writing to the database:
    ///
    /// • There can only be a single write transaction per database at any one time, so all write transactions must use `OWSPrimaryStorage`'s `dbReadWriteConnection`.
    /// • Executing a write transaction from within a write transaction causes a deadlock and must be avoided.
    @objc(writeWithBlock:)
    public static func write(with block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        // TODO: Right now this is kind of pointless, but the idea is to eventually
        // somehow manage nested write transactions in this class.
        owsStorage.dbReadWriteConnection.readWrite(block)
    }
}
