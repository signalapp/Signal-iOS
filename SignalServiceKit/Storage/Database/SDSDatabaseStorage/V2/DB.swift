//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

public protocol DB {

    // MARK: - Async Methods

    func asyncRead<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBReadTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    )

    func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    )

    func asyncWriteWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    )

    // MARK: - Awaitable Methods

    func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) async rethrows -> T

    func awaitableWriteWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) async -> T

    // MARK: - Promises

    func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T>

    func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T>

    // MARK: - Value Methods

    func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T

    func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T

    func writeWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) -> T

    // MARK: - Observation

    func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent
    )

    // MARK: - Touching

    func touch(interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction)

    /// See note on `shouldUpdateChatListUi` parameter in docs for ``TSGroupThread.updateWithGroupModel:shouldUpdateChatListUi:transaction``.
    func touch(thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction)

    func touch(storyMessage: StoryMessage, tx: DBWriteTransaction)
}

// MARK: - Default arguments

extension DB {

    // MARK: - Async Methods

    public func asyncRead<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBReadTransaction) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        asyncRead(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        asyncWriteWithTxCompletion(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    // MARK: - Awaitable Methods

    public func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws -> T
    ) async rethrows -> T {
        return try await awaitableWrite(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) async -> T {
        return await awaitableWriteWithTxCompletion(file: file, function: function, line: line, block: block)
    }

    // MARK: - Promises

    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T> {
        return readPromise(file: file, function: function, line: line, block)
    }

    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T> {
        return writePromise(file: file, function: function, line: line, block)
    }

    // MARK: - Value Methods

    public func read<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T {
        return try read(file: file, function: function, line: line, block: block)
    }

    public func write<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T {
        return try write(file: file, function: function, line: line, block: block)
    }

    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        return writeWithTxCompletion(file: file, function: function, line: line, block: block)
    }
}
