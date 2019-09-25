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

// MARK: -

// Serializes all transactions done using this queue.
@objc
public class GRDBDatabaseQueue: NSObject, SDSDatabaseQueue {
    private let storageAdapter: GRDBDatabaseStorageAdapter

    private let serialQueue = DispatchQueue(label: "org.signal.grdbDatabaseQueue")

    init(storageAdapter: GRDBDatabaseStorageAdapter) {
        self.storageAdapter = storageAdapter
    }

    @objc
    public func read(block: @escaping (GRDBReadTransaction) -> Void) {
        serialQueue.sync {
            do {
                try storageAdapter.read(block: block)
            } catch {
                owsFail("fatal error: \(error)")
            }
        }
    }

    @objc
    public func write(block: @escaping (GRDBWriteTransaction) -> Void) {
        serialQueue.sync {
            do {
                try storageAdapter.write(block: block)
            } catch {
                owsFail("fatal error: \(error)")
            }
        }
    }
}

// MARK: -

class YAPDBDatabaseQueue: SDSDatabaseQueue {
    private let databaseConnection: YapDatabaseConnection

    public init(databaseConnection: YapDatabaseConnection) {
        // We use DatabaseQueue's in places where we're especially concerned
        // about data consistency. To help ensure that our instances aren't being
        // mutated elsewhere we disable object caching on the connection.
        databaseConnection.objectCacheEnabled = false
        self.databaseConnection = databaseConnection
    }

    func read(block: @escaping (YapDatabaseReadTransaction) -> Void) {
        databaseConnection.read(block)
    }

    func write(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        databaseConnection.readWrite(block)
    }
}

// MARK: -

@objc
public class SDSAnyDatabaseQueue: SDSTransactable, SDSDatabaseQueue {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private let yapDatabaseQueue: YAPDBDatabaseQueue?
    private let grdbDatabaseQueue: GRDBDatabaseQueue?

    private let crossProcess: SDSCrossProcess

    init(yapDatabaseQueue: YAPDBDatabaseQueue?,
         grdbDatabaseQueue: GRDBDatabaseQueue?,
         crossProcess: SDSCrossProcess) {

        self.yapDatabaseQueue = yapDatabaseQueue
        self.grdbDatabaseQueue = grdbDatabaseQueue
        self.crossProcess = crossProcess
    }

    @objc
    public override func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        switch databaseStorage.dataStoreForReads {
        case .grdb:
            guard let grdbDatabaseQueue = grdbDatabaseQueue else {
                owsFail("Missing grdbDatabaseQueue.")
            }
            grdbDatabaseQueue.read { block($0.asAnyRead) }
        case .ydb:
            guard let yapDatabaseQueue = yapDatabaseQueue else {
                owsFail("Missing grdbDatabaseQueue.")
            }
            yapDatabaseQueue.read { block($0.asAnyRead) }
        }
    }

    @objc
    public override func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        switch databaseStorage.dataStoreForWrites {
        case .grdb:
            guard let grdbDatabaseQueue = grdbDatabaseQueue else {
                owsFail("Missing grdbDatabaseQueue.")
            }
            grdbDatabaseQueue.write { block($0.asAnyWrite) }
        case .ydb:
            guard let yapDatabaseQueue = yapDatabaseQueue else {
                owsFail("Missing grdbDatabaseQueue.")
            }
            yapDatabaseQueue.write { block($0.asAnyWrite) }
        }

        crossProcess.notifyChangedAsync()
    }
}
