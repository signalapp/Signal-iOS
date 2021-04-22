//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalClient

// MARK: - Any*Transaction

@objc
public class GRDBReadTransaction: NSObject {

    public let database: Database

    public let isUIRead: Bool

    public let startDate = Date()

    init(database: Database, isUIRead: Bool) {
        self.database = database
        self.isUIRead = isUIRead
    }

    @objc
    public var asAnyRead: SDSAnyReadTransaction {
        return SDSAnyReadTransaction(.grdbRead(self))
    }
}

// MARK: -

@objc
public class GRDBWriteTransaction: GRDBReadTransaction {

    private enum TransactionState {
        case open
        case finalizing
        case finalized
    }
    private var transactionState: TransactionState = .open

    init(database: Database) {
        super.init(database: database, isUIRead: false)
    }

    deinit {
        if transactionState != .finalized {
            owsFailDebug("Write transaction not finalized.")
        }
    }

    // This method must be called before the transaction is deallocated.
    @objc
    public func finalizeTransaction() {
        guard transactionState == .open else {
            owsFailDebug("Write transaction finalized more than once.")
            return
        }
        transactionState = .finalizing
        performTransactionFinalizationBlocks()
        transactionState = .finalized
    }

    @objc
    public var asAnyWrite: SDSAnyWriteTransaction {
        return SDSAnyWriteTransaction(.grdbWrite(self))
    }

    public typealias CompletionBlock = () -> Void
    internal var syncCompletions: [CompletionBlock] = []
    public struct AsyncCompletion {
        let queue: DispatchQueue
        let block: CompletionBlock
    }
    internal var asyncCompletions: [AsyncCompletion] = []

    @objc
    public func addSyncCompletion(block: @escaping CompletionBlock) {
        syncCompletions.append(block)
    }

    @objc
    public func addAsyncCompletion(queue: DispatchQueue, block: @escaping CompletionBlock) {
        asyncCompletions.append(AsyncCompletion(queue: queue, block: block))
    }

    fileprivate typealias TransactionFinalizationBlock = (_ transaction: GRDBWriteTransaction) -> Void
    private var transactionFinalizationBlocks = [String: TransactionFinalizationBlock]()
    private var removedFinalizationKeys = Set<String>()

    private func performTransactionFinalizationBlocks() {
        assert(transactionState == .finalizing)

        let blocksCopy = transactionFinalizationBlocks
        transactionFinalizationBlocks.removeAll()
        for (key, block) in blocksCopy {
            guard !removedFinalizationKeys.contains(key) else {
                continue
            }
            block(self)
        }
        assert(transactionFinalizationBlocks.isEmpty)
    }

    fileprivate func addTransactionFinalizationBlock(forKey key: String,
                                                     block: @escaping TransactionFinalizationBlock) {
        guard !removedFinalizationKeys.contains(key) else {
            // We shouldn't be adding finalizations for removed keys,
            // e.g. touching removed entities.
            owsFailDebug("Finalization unexpectedly added for removed key.")
            return
        }
        guard transactionState == .open else {
            // We're already finalizing; run the block immediately.
            block(self)
            return
        }
        if transactionFinalizationBlocks[key] != nil {
            if !DebugFlags.reduceLogChatter {
                Logger.verbose("De-duplicating.")
            }
        }
        // Always overwrite; we want to use the _last_ block.
        // For example, in the case of touching thread, a given
        // transaction might use multiple copies of a thread.
        // We want to touch the last copy of the thread that was
        // written to the database.
        transactionFinalizationBlocks[key] = block
    }

    fileprivate func addRemovedFinalizationKey(_ key: String) {
        guard !removedFinalizationKeys.contains(key) else {
            owsFailDebug("Finalization key removed twice.")
            return
        }
        removedFinalizationKeys.insert(key)
    }
}

// MARK: -

@objc
public class SDSAnyReadTransaction: NSObject {
    public enum ReadTransactionType {
        case grdbRead(_ transaction: GRDBReadTransaction)
    }

    public let readTransaction: ReadTransactionType
    public var startDate: Date {
        switch readTransaction {
        case .grdbRead(let grdbRead):
            return grdbRead.startDate
        }
    }

    init(_ readTransaction: ReadTransactionType) {
        self.readTransaction = readTransaction
    }

    public var isUIRead: Bool {
        switch readTransaction {
        case .grdbRead(let grdbRead):
            return grdbRead.isUIRead
        }
    }
}

@objc
public class SDSAnyWriteTransaction: SDSAnyReadTransaction, StoreContext {
    public enum WriteTransactionType {
        case grdbWrite(_ transaction: GRDBWriteTransaction)
    }

    public let writeTransaction: WriteTransactionType

    init(_ writeTransaction: WriteTransactionType) {
        self.writeTransaction = writeTransaction

        let readTransaction: ReadTransactionType
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            readTransaction = ReadTransactionType.grdbRead(grdbWrite)
        }

        super.init(readTransaction)
    }

    // NOTE: These completions are performed _after_ the write
    //       transaction has completed.
    @objc
    public func addSyncCompletion(_ block: @escaping () -> Void) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addSyncCompletion(block: block)
        }
    }

    // Objective-C doesn't honor default arguments.
    @objc
    public func addAsyncCompletion(_ block: @escaping () -> Void) {
        addAsyncCompletion(queue: DispatchQueue.main, block: block)
    }

    // Objective-C doesn't honor default arguments.
    @objc
    public func addAsyncCompletionOffMain(_ block: @escaping () -> Void) {
        addAsyncCompletion(queue: DispatchQueue.global(), block: block)
    }

    @objc
    public func addAsyncCompletion(queue: DispatchQueue = DispatchQueue.main, block: @escaping () -> Void) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addAsyncCompletion(queue: queue, block: block)
        }
    }

    private var threadUniqueIdsToIgnoreInteractionUpdates = Set<String>()

    @objc
    public func ignoreInteractionUpdates(forThreadUniqueId threadUniqueId: String) {
        threadUniqueIdsToIgnoreInteractionUpdates.insert(threadUniqueId)
    }

    @objc
    public func shouldIgnoreInteractionUpdates(forThreadUniqueId threadUniqueId: String) -> Bool {
        return threadUniqueIdsToIgnoreInteractionUpdates.contains(threadUniqueId)
    }

    public typealias TransactionFinalizationBlock = (SDSAnyWriteTransaction) -> Void

    @objc
    public func addTransactionFinalizationBlock(forKey key: String,
                                                block: @escaping TransactionFinalizationBlock) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addTransactionFinalizationBlock(forKey: key) { (transaction: GRDBWriteTransaction) in
                block(SDSAnyWriteTransaction(.grdbWrite(transaction)))
            }
        }
    }

    @objc
    public func addRemovedFinalizationKey(_ key: String) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addRemovedFinalizationKey(key)
        }
    }
}

// MARK: -

public extension StoreContext {
    var asTransaction: SDSAnyWriteTransaction {
        return self as! SDSAnyWriteTransaction
    }
}

// MARK: - Convenience Methods

public extension GRDBWriteTransaction {
    func executeUpdate(sql: String, arguments: StatementArguments = StatementArguments()) {
        do {
            let statement = try database.makeUpdateStatement(sql: sql)
            // TODO: We could use setArgumentsWithValidation for more safety.
            statement.unsafeSetArguments(arguments)
            try statement.execute()
        } catch {
            // If the attempt to write to GRDB flagged that the database was
            // corrupt, in addition to crashing we flag this so that we can
            // attempt to perform recovery.
            if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
                SSKPreferences.setHasGrdbDatabaseCorruption(true)
            }

            owsFail("Error: \(error)")
        }
    }

    // This has significant perf benefits over database.execute()
    // for queries that we perform repeatedly.
    func executeWithCachedStatement(sql: String,
                                    arguments: StatementArguments = StatementArguments()) {
        do {
            let statement = try database.cachedUpdateStatement(sql: sql)
            // TODO: We could use setArgumentsWithValidation for more safety.
            statement.unsafeSetArguments(arguments)
            try statement.execute()
        } catch {
            // If the attempt to write to GRDB flagged that the database was
            // corrupt, in addition to crashing we flag this so that we can
            // attempt to perform recovery.
            if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
                SSKPreferences.setHasGrdbDatabaseCorruption(true)
            }

            owsFail("Error: \(error)")
        }
    }
}

// MARK: -

@objc
public extension SDSAnyReadTransaction {
    var unwrapGrdbRead: GRDBReadTransaction {
        switch readTransaction {
        case .grdbRead(let grdbRead):
            return grdbRead
        }
    }
}

// MARK: -

@objc
public extension SDSAnyWriteTransaction {
    var unwrapGrdbWrite: GRDBWriteTransaction {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            return grdbWrite
        }
    }
}

// MARK: -

public extension GRDB.Database {
    final func throwsRead<T>(_ criticalSection: (_ database: GRDB.Database) throws -> T) throws -> T {
        do {
            return try criticalSection(self)
        } catch {
            // If the attempt to write to GRDB flagged that the database was
            // corrupt, in addition to crashing we flag this so that we can
            // attempt to perform recovery.
            if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
                SSKPreferences.setHasGrdbDatabaseCorruption(true)
                owsFail("Error: \(error)")
            }
            owsFailDebug("Error: \(error)")
            throw error
        }
    }

    final func strictRead<T>(_ criticalSection: (_ database: GRDB.Database) throws -> T) -> T {
        do {
            return try criticalSection(self)
        } catch {
            // If the attempt to write to GRDB flagged that the database was
            // corrupt, in addition to crashing we flag this so that we can
            // attempt to perform recovery.
            if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
                SSKPreferences.setHasGrdbDatabaseCorruption(true)
                owsFail("Error: \(error)")
            }
            owsFail("Error: \(error)")
        }
    }
}
