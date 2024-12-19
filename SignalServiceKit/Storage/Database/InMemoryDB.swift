//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

#if TESTABLE_BUILD

public final class InMemoryDB: DB {

    private let schedulers: Schedulers

    public init(schedulers: Schedulers = DispatchQueueSchedulers()) {
        self.schedulers = schedulers
    }

    // MARK: - Transactions

    public class ReadTransaction: DBReadTransaction {
        let db: Database
        init(db: Database) {
            self.db = db
        }

        public var databaseConnection: GRDB.Database { db }
    }

    public final class WriteTransaction: ReadTransaction, DBWriteTransaction {

        fileprivate var syncCompletions = [() -> Void]()
        fileprivate var asyncCompletions = [(Scheduler, () -> Void)]()

        public func addFinalization(forKey key: String, block: @escaping () -> Void) {
            fatalError()
        }
        public func addSyncCompletion(_ block: @escaping () -> Void) {
            syncCompletions.append(block)
        }
        public func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
            asyncCompletions.append((scheduler, block))
        }
    }

    // MARK: - State

    public let databaseQueue: DatabaseQueue = {
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
        block: @escaping (ReadTransaction) -> T,
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
        block: @escaping (WriteTransaction) -> T,
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
        block: @escaping (WriteTransaction) -> TransactionCompletion<T>,
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
        block: (WriteTransaction) throws -> T
    ) async rethrows -> T {
        await Task.yield()
        return try write(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) async -> T {
        await Task.yield()
        return writeWithTxCompletion(file: file, function: function, line: line, block: block)
    }

    public func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (ReadTransaction) throws -> T
    ) -> Promise<T> {
        return Promise.wrapAsync { try self.read(file: file, function: function, line: line, block: block) }
    }

    public func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (WriteTransaction) throws -> T
    ) -> Promise<T> {
        return Promise.wrapAsync { try await self.awaitableWrite(file: file, function: function, line: line, block: block) }
    }

    // MARK: - Value Methods

    public func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (ReadTransaction) throws -> T
    ) rethrows -> T {
        return try _read(block: block, rescue: { throw $0 })
    }

    private func _read<T>(block: (ReadTransaction) throws -> T, rescue: (Error) throws -> Never) rethrows -> T {
        var thrownError: Error?
        let result: T? = try! databaseQueue.read { db in
            do {
                return try block(ReadTransaction(db: db))
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
        block: (WriteTransaction) throws -> T
    ) rethrows -> T {
        return try _writeCommitIfThrows(block: block, rescue: { throw $0 })
    }

    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        return _writeWithTxCompletion(block: block)
    }

    private func _writeCommitIfThrows<T>(
        block: (WriteTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) rethrows -> T {
        var thrownError: Error?
        var syncCompletions: [() -> Void]!
        var asyncCompletions: [(Scheduler, () -> Void)]!
        let result: T? = try! databaseQueue.write { db in
            do {
                let tx = WriteTransaction(db: db)
                defer {
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
            $0.0.async($0.1)
        }
        if let thrownError {
            try rescue(thrownError)
        }
        return result!
    }

    private func _writeWithTxCompletion<T>(
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        var syncCompletions: [() -> Void]!
        var asyncCompletions: [(Scheduler, () -> Void)]!
        let result: T = try! databaseQueue.writeWithoutTransaction { db in
            var result: T!
            try db.inTransaction {
                let tx = WriteTransaction(db: db)
                defer {
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
            $0.0.async($0.1)
        }
        return result
    }

    // MARK: - Helpers

    func fetchExactlyOne<T: SDSCodableModel>(modelType: T.Type) -> T? {
        let all = try! read { tx in try modelType.fetchAll(tx.db) }
        guard all.count == 1 else { return nil }
        return all.first!
    }

    func insert<T: PersistableRecord>(record: T) {
        try! write { tx in try record.insert(tx.db) }
    }

    func update<T: PersistableRecord>(record: T) {
        try! write { tx in try record.update(tx.db) }
    }

    func remove<T: PersistableRecord>(model record: T) {
        _ = try! write { tx in try record.delete(tx.db) }
    }

    public func touch(_ interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    public func touch(_ thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    public func touch(_ storyMessage: StoryMessage, tx: DBWriteTransaction) {
        // Do nothing.
    }
}

#endif
