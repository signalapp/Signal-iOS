//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

public import GRDB

public final class InMemoryDB: DB {
    public enum Mode {
        case normalXcodeBuild
        case xcodePreview
    }

    let databaseQueue: DatabaseQueue

    public init() {
        self.databaseQueue = DatabaseQueue()

        let schemaUrl: URL
        if
            let urlInNormalPlace = Bundle(for: GRDBSchemaMigrator.self)
                .url(forResource: "schema", withExtension: "sql")
        {
            schemaUrl = urlInNormalPlace
        } else if
            let urlInWonkyPlace = Bundle(for: GRDBSchemaMigrator.self)
                .url(forResource: "schema", withExtension: "sql", subdirectory: "Frameworks/SignalServiceKit.framework")
        {
            /// There's what appears to be a bug in Xcode 16.3, in which for
            /// Xcode Previews, sometimes, the Bundle returned for SSK types
            /// refers to the top-level app bundle, not the SSK bundle.
            /// Searching in that bundle will fail to find `schema.sql`; so
            /// instead manually search in the SSK subdirectory.
            ///
            /// If we go a while without noticing the warning print below, we
            /// can remove this and see what happens.
            ///
            /// Note that Logger doesn't work in Xcode Previews, hence print!
            print("Warning: needed to use fallback schema.sql location!")
            schemaUrl = urlInWonkyPlace
        } else {
            owsFail("Failed to find schema.sql in Bundle!")
        }

        try! databaseQueue.write { try $0.execute(sql: try String(contentsOf: schemaUrl)) }
    }

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
        DispatchQueue.global().async {
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
        DispatchQueue.global().async {
            let result = self.write(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        DispatchQueue.global().async {
            let result = self.writeWithTxCompletion(file: file, function: function, line: line, block: block)
            if let completion { completionQueue.async({ completion(result) }) }
        }
    }

    public func awaitableWrite<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) async throws(E) -> T {
        await Task.yield()
        return try write(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithRollbackIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) async throws(E) -> T {
        await Task.yield()
        return try writeWithRollbackIfThrows(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) async -> T {
        await Task.yield()
        return writeWithTxCompletion(file: file, function: function, line: line, block: block)
    }

    // MARK: - Value Methods

    public func read<T, E: Error>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws(E) -> T
    ) throws(E) -> T {
        return try _read(block: block, rescue: { err throws(E) in throw err })
    }

    private func _read<T, E: Error>(block: (DBReadTransaction) throws(E) -> T, rescue: (E) throws(E) -> Never) throws(E) -> T {
        var thrownError: E?
        let result: T? = try! databaseQueue.read { db in
            do throws(E) {
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

    public func write<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) throws(E) -> T {
        return try _writeWithTxCompletionIfThrows(
            block: block,
            completionIfThrows: .commit(()),
            rescue: { err throws(E) in throw err }
        )
    }

    public func writeWithRollbackIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T
    ) throws(E) -> T {
        return try _writeWithTxCompletionIfThrows(
            block: block,
            completionIfThrows: .rollback(()),
            rescue: { err throws(E) in throw err }
        )
    }

    public func writeWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        return _writeWithTxCompletion(block: block)
    }

    private func _writeWithTxCompletionIfThrows<T, E>(
        block: (DBWriteTransaction) throws(E) -> T,
        completionIfThrows: TransactionCompletion<Void>,
        rescue: (E) throws(E) -> Never,
    ) throws(E) -> T {
        var result: T!
        var thrown: E?
        _writeWithTxCompletion { tx in
            do throws(E) {
                result = try block(tx)
                return .commit(())
            } catch {
                thrown = error
                return completionIfThrows
            }
        }
        if let thrown {
            try rescue(thrown)
        }
        return result!
    }

    private func _writeWithTxCompletion<T>(
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        var txCompletionBlocks: [DBWriteTransaction.CompletionBlock]!
        let result: T = try! databaseQueue.writeWithoutTransaction { db in
            var result: T!
            try db.inTransaction {
                let tx = DBWriteTransaction(database: db)
                defer {
                    tx.finalizeTransaction()
                    txCompletionBlocks = tx.completionBlocks
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
        txCompletionBlocks.forEach { $0() }
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
