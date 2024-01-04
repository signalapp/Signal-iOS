//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

#if TESTABLE_BUILD

final class InMemoryDB: DB {
    // MARK: - Transactions

    class ReadTransaction: DBReadTransaction {
        let db: Database
        init(db: Database) {
            self.db = db
        }
    }

    static func shimOnlyBridge(_ tx: DBReadTransaction) -> ReadTransaction {
        return tx as! ReadTransaction
    }

    final class WriteTransaction: ReadTransaction, DBWriteTransaction {
        func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
            fatalError()
        }
    }

    static func shimOnlyBridge(_ tx: DBWriteTransaction) -> WriteTransaction {
        return tx as! WriteTransaction
    }

    // MARK: - State

    private let databaseQueue: DatabaseQueue = {
        let result = DatabaseQueue()
        let schemaUrl = Bundle(for: GRDBSchemaMigrator.self).url(forResource: "schema", withExtension: "sql")!
        try! result.write { try $0.execute(sql: try String(contentsOf: schemaUrl)) }
        return result
    }()

    // MARK: - Protocol

    func appendDbChangeDelegate(_ dbChangeDelegate: DBChangeDelegate) { fatalError() }

    func asyncRead(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBReadTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    ) {
        DispatchQueue.global().async {
            self.read(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async(completion) }
        }
    }

    func asyncWrite(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    ) {
        DispatchQueue.global().async {
            self.write(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async(completion) }
        }
    }

    func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) throws -> T
    ) async rethrows -> T {
        await Task.yield()
        return try write(file: file, function: function, line: line, block: block)
    }

    func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T> {
        return Promise.wrapAsync { try self.read(file: file, function: function, line: line, block: block) }
    }

    func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T> {
        return Promise.wrapAsync { try await self.awaitableWrite(file: file, function: function, line: line, block: block) }
    }

    // MARK: - Value Methods

    func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T {
        return try _read(block: block, rescue: { throw $0 })
    }

    private func _read<T>(block: (DBReadTransaction) throws -> T, rescue: (Error) throws -> Void) rethrows -> T {
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
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T {
        return try _write(block: block, rescue: { throw $0 })
    }

    private func _write<T>(
        block: (DBWriteTransaction) throws -> T,
        rescue: (Error) throws -> Void
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
        let all = try! read { tx in try modelType.fetchAll(Self.shimOnlyBridge(tx).db) }
        guard all.count == 1 else { return nil }
        return all.first!
    }

    func insert<T: PersistableRecord>(record: T) {
        try! write { tx in try record.insert(Self.shimOnlyBridge(tx).db) }
    }

    func update<T: PersistableRecord>(record: T) {
        try! write { tx in try record.update(Self.shimOnlyBridge(tx).db) }
    }

    func remove<T: PersistableRecord>(model record: T) {
        _ = try! write { tx in try record.delete(Self.shimOnlyBridge(tx).db) }
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
