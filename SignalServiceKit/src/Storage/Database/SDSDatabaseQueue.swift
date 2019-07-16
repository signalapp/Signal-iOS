//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

protocol SDSDatabaseQueue {
    associatedtype ReadTransaction
    associatedtype WriteTransaction
    func read(block: @escaping (ReadTransaction) -> Void)
    func write(block: @escaping (WriteTransaction) -> Void)
}

@objc
public class GRDBDatabaseQueue: NSObject, SDSDatabaseQueue {
    let databaseQueue: DatabaseQueue
    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    @objc
    public func read(block: @escaping (GRDBReadTransaction) -> Void) {
        databaseQueue.read { database in
            autoreleasepool {
                block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func write(block: @escaping (GRDBWriteTransaction) -> Void) {
        do {
            try databaseQueue.write { database in
                try autoreleasepool {
                    block(GRDBWriteTransaction(database: database))
                }
            }
        } catch {
            owsFail("fatal error: \(error)")
        }
    }

    var asAnyQueue: SDSAnyDatabaseQueue {
        return SDSAnyDatabaseQueue(grdbDatabaseQueue: self)
    }
}

class YAPDBDatabaseQueue: SDSDatabaseQueue {
    private let databaseConnection: YapDatabaseConnection

    public init(databaseConnection: YapDatabaseConnection) {
        // We use DatabaseQueue's in places where we're especially concerned
        // about data consistency. To help ensure that our instances aren't being
        // mutated elsewhere we disable object caching on the connection
        databaseConnection.objectCacheEnabled = false
        self.databaseConnection = databaseConnection
    }

    func read(block: @escaping (YapDatabaseReadTransaction) -> Void) {
        databaseConnection.read(block)
    }

    func write(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        databaseConnection.readWrite(block)
    }

    var asAnyQueue: SDSAnyDatabaseQueue {
        return SDSAnyDatabaseQueue(yapDatabaseQueue: self)
    }
}

@objc
public class SDSAnyDatabaseQueue: NSObject, SDSDatabaseQueue {
    enum SomeDatabaseQueue {
        case yap(_ yapQueue: YAPDBDatabaseQueue)
        case grdb(_ grdbQueue: GRDBDatabaseQueue)
    }

    private let someDatabaseQueue: SomeDatabaseQueue

    init(yapDatabaseQueue: YAPDBDatabaseQueue) {
        someDatabaseQueue = .yap(yapDatabaseQueue)
    }

    init(grdbDatabaseQueue: GRDBDatabaseQueue) {
        someDatabaseQueue = .grdb(grdbDatabaseQueue)
    }

    @objc
    func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        switch someDatabaseQueue {
        case .yap(let yapDatabaseQueue):
            yapDatabaseQueue.read { block($0.asAnyRead) }
        case .grdb(let grdbDatabaseQueue):
            grdbDatabaseQueue.read { block($0.asAnyRead) }
        }
    }

    @objc
    func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        switch someDatabaseQueue {
        case .yap(let yapDatabaseQueue):
            yapDatabaseQueue.write { block($0.asAnyWrite) }
        case .grdb(let grdbDatabaseQueue):
            grdbDatabaseQueue.write { block($0.asAnyWrite) }
        }
    }

    // MARK: - Async Methods

    @objc
    public func asyncRead(block: @escaping (SDSAnyReadTransaction) -> Void) {
        asyncRead(block: block, completion: { })
    }

    @objc
    public func asyncRead(block: @escaping (SDSAnyReadTransaction) -> Void, completion: @escaping () -> Void) {
        asyncRead(block: block, completionQueue: .main, completion: completion)
    }

    @objc
    public func asyncRead(block: @escaping (SDSAnyReadTransaction) -> Void, completionQueue: DispatchQueue, completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.read(block: block)

            completionQueue.async(execute: completion)
        }
    }

    @objc
    public func asyncWrite(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        asyncWrite(block: block, completion: { })
    }

    @objc
    public func asyncWrite(block: @escaping (SDSAnyWriteTransaction) -> Void, completion: @escaping () -> Void) {
        asyncWrite(block: block, completionQueue: .main, completion: completion)
    }

    @objc
    public func asyncWrite(block: @escaping (SDSAnyWriteTransaction) -> Void, completionQueue: DispatchQueue, completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.write(block: block)

            completionQueue.async(execute: completion)
        }
    }
}
