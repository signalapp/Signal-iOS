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
        completion: ((T) -> Void)?,
    )

    func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?,
    )

    // MARK: - Awaitable Methods

    func awaitableWrite<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T,
    ) async throws(E) -> T

    func awaitableWriteWithRollbackIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T,
    ) async throws(E) -> T

    // MARK: - Value Methods

    func read<T, E: Error>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws(E) -> T,
    ) throws(E) -> T

    func write<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T,
    ) throws(E) -> T

    func writeWithRollbackIfThrows<T, E>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws(E) -> T,
    ) throws(E) -> T

    // MARK: - Observation

    func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent,
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
        completion: ((T) -> Void)? = nil,
    ) {
        asyncRead(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil,
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    // MARK: - Awaitable Methods

    public func awaitableWrite<T, E>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws(E) -> T,
    ) async throws(E) -> T {
        return try await awaitableWrite(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithRollbackIfThrows<T, E>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws(E) -> T,
    ) async throws(E) -> T {
        return try await awaitableWriteWithRollbackIfThrows(file: file, function: function, line: line, block: block)
    }

    // MARK: - Value Methods

    public func read<T, E: Error>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBReadTransaction) throws(E) -> T,
    ) throws(E) -> T {
        return try read(file: file, function: function, line: line, block: block)
    }

    public func write<T, E: Error>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws(E) -> T,
    ) throws(E) -> T {
        return try write(file: file, function: function, line: line, block: block)
    }

    public func writeWithRollbackIfThrows<T, E>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws(E) -> T,
    ) throws(E) -> T {
        return try writeWithRollbackIfThrows(file: file, function: function, line: line, block: block)
    }
}
