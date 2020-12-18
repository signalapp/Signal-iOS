import YapDatabase

@objc public protocol OWSPrimaryStorageProtocol {

    var dbReadConnection: YapDatabaseConnection { get }
    var dbReadWriteConnection: YapDatabaseConnection { get }
}
