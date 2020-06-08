//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

// MARK: - Any*Transaction

@objc
public class GRDBReadTransaction: NSObject {

    public let database: Database

    public let isUIRead: Bool

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
        if transactionState == .finalized {
            owsFailDebug("Write transaction not finalized.")
        }
    }

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

    internal var syncCompletions: [() -> Void] = []
    internal var asyncCompletions: [(DispatchQueue, () -> Void)] = []

    @objc
    public func addSyncCompletion(block: @escaping () -> Void) {
        syncCompletions.append(block)
    }

    @objc
    public func addAsyncCompletion(queue: DispatchQueue, block: @escaping () -> Void) {
        asyncCompletions.append((queue, block))
    }

    fileprivate typealias TransactionFinalizationBlock = (_ transaction: GRDBWriteTransaction) -> Void
    private var transactionFinalizationBlocks = [String: TransactionFinalizationBlock]()

    private func performTransactionFinalizationBlocks() {
        assert(transactionState == .finalizing)

        let blocks = transactionFinalizationBlocks.values
        transactionFinalizationBlocks.removeAll()
        for block in blocks {
            block(self)
        }
        assert(transactionFinalizationBlocks.isEmpty)
    }

    fileprivate func addTransactionFinalizationBlock(forKey key: String,
                                                     block: @escaping TransactionFinalizationBlock) {
        guard transactionState == .open else {
            // We're already finalizing; run the block immediately.
            block(self)
            return
        }
        guard transactionFinalizationBlocks[key] == nil else {
            // Ignoring duplicate.
            Logger.verbose("Ignoring duplicate.")
            return
        }
        transactionFinalizationBlocks[key] = block
    }
}

// MARK: -

// Type erased transactions are generated at the top level (by DatabaseStorage) and can then be
// passed through an adapter which will be backed by either YapDB or GRDB
//
// To faciliate a gradual migration to GRDB features without breaking existing Yap functionality
// there are backdoors like `transitional_yapReadTransaction` which will unwrap
// the underlying YapDatabaseRead/WriteTransaction.
@objc
public class SDSAnyReadTransaction: NSObject, SPKProtocolReadContext {
    public enum ReadTransactionType {
        case yapRead(_ transaction: YapDatabaseReadTransaction)
        case grdbRead(_ transaction: GRDBReadTransaction)
    }

    public let readTransaction: ReadTransactionType

    init(_ readTransaction: ReadTransactionType) {
        self.readTransaction = readTransaction
    }

    // MARK: Transitional Methods

    // Useful to delineate where we're using SDSAnyReadTransaction if a specific
    // feature hasn't been migrated and still requires a YapDatabaseReadTransaction

    @objc
    public init(transitional_yapReadTransaction: YapDatabaseReadTransaction) {
        self.readTransaction = .yapRead(transitional_yapReadTransaction)
    }

    @objc
    public var transitional_yapReadTransaction: YapDatabaseReadTransaction? {
        switch readTransaction {
        case .yapRead(let yapRead):
            return yapRead
        case .grdbRead:
            return nil
        }
    }

    @objc
    public var isUIRead: Bool {
        switch readTransaction {
        case .yapRead:
            return false
        case .grdbRead(let grdbRead):
            return grdbRead.isUIRead
        }
    }
}

@objc
public class SDSAnyWriteTransaction: SDSAnyReadTransaction, SPKProtocolWriteContext {
    public enum WriteTransactionType {
        case yapWrite(_ transaction: YapDatabaseReadWriteTransaction)
        case grdbWrite(_ transaction: GRDBWriteTransaction)
    }

    public let writeTransaction: WriteTransactionType

    init(_ writeTransaction: WriteTransactionType) {
        self.writeTransaction = writeTransaction

        let readTransaction: ReadTransactionType
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            readTransaction = ReadTransactionType.yapRead(yapWrite)
        case .grdbWrite(let grdbWrite):
            readTransaction = ReadTransactionType.grdbRead(grdbWrite)
        }

        super.init(readTransaction)
    }

    // MARK: Transitional Methods

    // Useful to delineate where we're using SDSAnyReadTransaction if a specific
    // feature hasn't been migrated and still requires a YapDatabaseReadTransaction

    @objc
    public init(transitional_yapWriteTransaction: YapDatabaseReadWriteTransaction) {
        self.writeTransaction = .yapWrite(transitional_yapWriteTransaction)

        super.init(transitional_yapReadTransaction: transitional_yapWriteTransaction)
    }

    // GRDB TODO: Remove this method.
    @objc
    public var transitional_yapWriteTransaction: YapDatabaseReadWriteTransaction? {
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            return yapWrite
        case .grdbWrite:
            return nil
        }
    }

    // NOTE: These completions are performed _after_ the write
    //       transaction has completed.
    @objc
    public func addSyncCompletion(_ block: @escaping () -> Void) {
        switch writeTransaction {
        case .yapWrite:
            owsFailDebug("YDB transactions don't support sync completions.")
        case .grdbWrite(let grdbWrite):
            grdbWrite.addSyncCompletion(block: block)
        }
    }

    // Objective-C doesn't honor default arguments.
    @objc
    public func addAsyncCompletion(_ block: @escaping () -> Void) {
        addAsyncCompletion(queue: DispatchQueue.main, block: block)
    }

    @objc
    public func addAsyncCompletion(queue: DispatchQueue = DispatchQueue.main, block: @escaping () -> Void) {
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            yapWrite.addCompletionQueue(queue, completionBlock: block)
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
        case .yapWrite:
            // YDB transactions don't support deferred transaction finalizations.
            block(self)
        case .grdbWrite(let grdbWrite):
            grdbWrite.addTransactionFinalizationBlock(forKey: key) { (transaction: GRDBWriteTransaction) in
                block(SDSAnyWriteTransaction(.grdbWrite(transaction)))
            }
        }
    }
}

// MARK: -

@objc
public extension YapDatabaseReadTransaction {
    var asAnyRead: SDSAnyReadTransaction {
        return SDSAnyReadTransaction(transitional_yapReadTransaction: self)
    }
}

// MARK: -

@objc
public extension YapDatabaseReadWriteTransaction {
    var asAnyWrite: SDSAnyWriteTransaction {
        return SDSAnyWriteTransaction(transitional_yapWriteTransaction: self)
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
            owsFail("Error: \(error)")
        }
    }
}

// MARK: -

@objc
public extension SDSAnyReadTransaction {
    var unwrapGrdbRead: GRDBReadTransaction {
        switch readTransaction {
        case .yapRead:
            owsFail("Invalid transaction type.")
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
        case .yapWrite:
            owsFail("Invalid transaction type.")
        case .grdbWrite(let grdbWrite):
            return grdbWrite
        }
    }
}
