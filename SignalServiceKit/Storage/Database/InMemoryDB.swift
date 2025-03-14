//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

public import GRDB

public final class InMemoryDB: DB {

    private let schedulers: Schedulers

    public init(schedulers: Schedulers = DispatchQueueSchedulers()) {
        self.schedulers = schedulers
    }

    // MARK: - State

    let databaseQueue: DatabaseQueue = {
        let result = DatabaseQueue()
        let schemaUrl = Bundle(for: GRDBSchemaMigrator.self).url(forResource: "schema", withExtension: "sql")!
        try! result.write { try $0.execute(sql: try String(contentsOf: schemaUrl)) }
        return result
    }()

    // MARK: - Protocol

    public func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent
    ) {
        databaseQueue.add(transactionObserver: transactionObserver, extent: extent)
    }

    public func asyncRead<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBReadTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        schedulers.global().async {
            let result: T = self.read(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    public func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        schedulers.global().async {
            let result = self.write(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        schedulers.global().async {
            let result = self.writeWithTxCompletion(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    public func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) async rethrows -> T {
        await Task.yield()
        return try write(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) async -> T {
        await Task.yield()
        return writeWithTxCompletion(file: file, function: function, line: line, block: block)
    }

    // MARK: - Value Methods

    public func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T {
        return try _read(block: block, rescue: { throw $0 })
    }

    private func _read<T>(block: (DBReadTransaction) throws -> T, rescue: (Error) throws -> Never) rethrows -> T {
        var thrownError: Error?
        let result: T? = try! databaseQueue.read { db in
            do {
                return try block(DBReadTransaction(database: db))
            } catch {
                thrownError = error
                return nil
            }
        }
        if let thrownError {
            try rescue(thrownError)
        }
        return result!
    }

    public func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T {
        return try _writeCommitIfThrows(block: block, rescue: { throw $0 })
    }

    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        return _writeWithTxCompletion(block: block)
    }

    private func _writeCommitIfThrows<T>(
        block: (DBWriteTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) rethrows -> T {
        var thrownError: Error?
        var syncCompletions: [DBWriteTransaction.SyncCompletion]!
        var asyncCompletions: [DBWriteTransaction.AsyncCompletion]!
        let result: T? = try! databaseQueue.write { db in
            do {
                let tx = DBWriteTransaction(database: db)
                defer {
                    tx.finalizeTransaction()
                    syncCompletions = tx.syncCompletions
                    asyncCompletions = tx.asyncCompletions
                }
                return try block(tx)
            } catch {
                thrownError = error
                return nil
            }
        }
        syncCompletions.forEach {
            $0()
        }
        asyncCompletions.forEach {
            $0.scheduler.async($0.block)
        }
        if let thrownError {
            try rescue(thrownError)
        }
        return result!
    }

    private func _writeWithTxCompletion<T>(
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        var syncCompletions: [DBWriteTransaction.SyncCompletion]!
        var asyncCompletions: [DBWriteTransaction.AsyncCompletion]!
        let result: T = try! databaseQueue.writeWithoutTransaction { db in
            var result: T!
            try db.inTransaction {
                let tx = DBWriteTransaction(database: db)
                defer {
                    tx.finalizeTransaction()
                    syncCompletions = tx.syncCompletions
                    asyncCompletions = tx.asyncCompletions
                }
                switch block(tx) {
                case .commit(let t):
                    result = t
                    return .commit
                case .rollback(let t):
                    result = t
                    return .rollback
                }
            }
            return result
        }
        syncCompletions.forEach {
            $0()
        }
        asyncCompletions.forEach {
            $0.scheduler.async($0.block)
        }
        return result
    }

    // MARK: - Helpers

    func fetchExactlyOne<T: SDSCodableModel>(modelType: T.Type) -> T? {
        let all = try! read { tx in try modelType.fetchAll(tx.database) }
        guard all.count == 1 else { return nil }
        return all.first!
    }

    func insert<T: PersistableRecord>(record: T) {
        try! write { tx in try record.insert(tx.database) }
    }

    func update<T: PersistableRecord>(record: T) {
        try! write { tx in try record.update(tx.database) }
    }

    func remove<T: PersistableRecord>(model record: T) {
        _ = try! write { tx in try record.delete(tx.database) }
    }

    public func touch(interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    public func touch(thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    public func touch(storyMessage: StoryMessage, tx: DBWriteTransaction) {
        // Do nothing.
    }
}

#endif
