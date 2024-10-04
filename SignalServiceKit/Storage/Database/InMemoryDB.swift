//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

#if TESTABLE_BUILD

final class InMemoryDB: DB {
    // MARK: - Transactions

    class ReadTransaction: DBReadTransaction {
        let db: Database
        init(db: Database) {
            self.db = db
        }
    }

    final class WriteTransaction: ReadTransaction, DBWriteTransaction {
        func addFinalization(forKey key: String, block: @escaping () -> Void) {
            fatalError()
        }
        func addSyncCompletion(_ block: @escaping () -> Void) {
            fatalError()
        }
        func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
            fatalError()
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

    func appendDbChangeDelegate(_ dbChangeDelegate: DBChangeDelegate) { fatalError() }

    func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent
    ) {
        databaseQueue.add(transactionObserver: transactionObserver, extent: extent)
    }

    func asyncRead<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (ReadTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        DispatchQueue.global().async {
            let result: T = self.read(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (WriteTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        DispatchQueue.global().async {
            let result = self.write(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (WriteTransaction) throws -> T
    ) async rethrows -> T {
        await Task.yield()
        return try write(file: file, function: function, line: line, block: block)
    }

    func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (ReadTransaction) throws -> T
    ) -> Promise<T> {
        return Promise.wrapAsync { try self.read(file: file, function: function, line: line, block: block) }
    }

    func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (WriteTransaction) throws -> T
    ) -> Promise<T> {
        return Promise.wrapAsync { try await self.awaitableWrite(file: file, function: function, line: line, block: block) }
    }

    // MARK: - Value Methods

    func read<T>(
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

    func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (WriteTransaction) throws -> T
    ) rethrows -> T {
        return try _write(block: block, rescue: { throw $0 })
    }

    private func _write<T>(
        block: (WriteTransaction) throws -> T,
        rescue: (Error) throws -> Never
    ) rethrows -> T {
        var thrownError: Error?
        let result: T? = try! databaseQueue.write { db in
            do {
                return try block(WriteTransaction(db: db))
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

    func touch(_ interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    func touch(_ thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    func touch(_ storyMessage: StoryMessage, tx: DBWriteTransaction) {
        // Do nothing.
    }
}

#endif
