//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

// MARK: - Any*Transaction

public class GRDBReadTransaction {

    public let database: Database

    public let startDate = Date()

    init(database: Database) {
        self.database = database
    }

    public var asAnyRead: SDSAnyReadTransaction {
        return SDSAnyReadTransaction(.grdbRead(self))
    }
}

// MARK: -

public class GRDBWriteTransaction: GRDBReadTransaction {

    private enum TransactionState {
        case open
        case finalizing
        case finalized
    }
    private var transactionState: TransactionState = .open

    override init(database: Database) {
        super.init(database: database)
    }

    deinit {
        if transactionState != .finalized {
            owsFailDebug("Write transaction not finalized.")
        }
    }

    // This method must be called before the transaction is deallocated.
    public func finalizeTransaction() {
        guard transactionState == .open else {
            owsFailDebug("Write transaction finalized more than once.")
            return
        }
        transactionState = .finalizing
        performTransactionFinalizationBlocks()
        transactionState = .finalized
    }

    public var asAnyWrite: SDSAnyWriteTransaction {
        return SDSAnyWriteTransaction(.grdbWrite(self))
    }

    public typealias CompletionBlock = () -> Void
    internal var syncCompletions: [CompletionBlock] = []
    public struct AsyncCompletion {
        let scheduler: Scheduler
        let block: CompletionBlock
    }
    internal var asyncCompletions: [AsyncCompletion] = []

    public func addSyncCompletion(block: @escaping CompletionBlock) {
        syncCompletions.append(block)
    }

    public func addAsyncCompletion(queue: DispatchQueue, block: @escaping CompletionBlock) {
        addAsyncCompletion(on: queue, block: block)
    }

    public func addAsyncCompletion(on scheduler: Scheduler, block: @escaping CompletionBlock) {
        asyncCompletions.append(AsyncCompletion(scheduler: scheduler, block: block))
    }

    fileprivate typealias TransactionFinalizationBlock = (_ transaction: GRDBWriteTransaction) -> Void
    private var transactionFinalizationBlocks = [String: TransactionFinalizationBlock]()

    private func performTransactionFinalizationBlocks() {
        assert(transactionState == .finalizing)

        let blocksCopy = transactionFinalizationBlocks
        transactionFinalizationBlocks.removeAll()
        for (_, block) in blocksCopy {
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
        // Always overwrite; we want to use the _last_ block.
        // For example, in the case of touching thread, a given
        // transaction might use multiple copies of a thread.
        // We want to touch the last copy of the thread that was
        // written to the database.
        transactionFinalizationBlocks[key] = block
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

    /// Run the given block synchronously after the transaction is finalized.
    public func addSyncCompletion(_ block: @escaping () -> Void) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addSyncCompletion(block: block)
        }
    }

    /// Schedule the given block to run on `scheduler` after the transaction is
    /// finalized.
    public func addAsyncCompletion(on scheduler: Scheduler, block: @escaping () -> Void) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addAsyncCompletion(on: scheduler, block: block)
        }
    }

    /// Schedule the given block to run just before this transaction is
    /// finalized.
    ///
    /// - Important
    /// `block` must not capture any database models, as they may no longer be
    /// valid by time the transaction finalizes.
    public func addTransactionFinalizationBlock(
        forKey key: String,
        block: @escaping (SDSAnyWriteTransaction) -> Void
    ) {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbWrite.addTransactionFinalizationBlock(forKey: key) { (transaction: GRDBWriteTransaction) in
                block(SDSAnyWriteTransaction(.grdbWrite(transaction)))
            }
        }
    }
}

// MARK: -

public extension StoreContext {
    var asTransaction: SDSAnyWriteTransaction {
        return self as! SDSAnyWriteTransaction
    }
}

// MARK: -

public extension SDSAnyReadTransaction {
    var unwrapGrdbRead: GRDBReadTransaction {
        switch readTransaction {
        case .grdbRead(let grdbRead):
            return grdbRead
        }
    }
}

// MARK: -

public extension SDSAnyWriteTransaction {
    var unwrapGrdbWrite: GRDBWriteTransaction {
        switch writeTransaction {
        case .grdbWrite(let grdbWrite):
            return grdbWrite
        }
    }
}
