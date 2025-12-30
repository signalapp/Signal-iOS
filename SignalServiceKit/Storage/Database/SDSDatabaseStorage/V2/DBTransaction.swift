//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import GRDB

@objc
public class DBReadTransaction: NSObject {
    public let database: Database
    public let startDate: MonotonicDate

    init(database: Database) {
        self.database = database
        self.startDate = MonotonicDate()
    }
}

@objc
public class DBWriteTransaction: DBReadTransaction, LibSignalClient.StoreContext {
    private enum TransactionState {
        case open
        case finalizing
        case finalized
    }

    typealias FinalizationBlock = (DBWriteTransaction) -> Void
    typealias CompletionBlock = () -> Void

    private var transactionState: TransactionState
    private var finalizationBlocks: [String: FinalizationBlock]
    private(set) var completionBlocks: [CompletionBlock]

    override init(database: Database) {
        self.transactionState = .open
        self.finalizationBlocks = [:]
        self.completionBlocks = []

        super.init(database: database)
    }

    deinit {
        owsAssertDebug(
            transactionState == .finalized,
            "Write transaction deallocated without finalization!",
        )
    }

    // MARK: -

    func finalizeTransaction() {
        guard transactionState == .open else {
            owsFailDebug("Write transaction finalized multiple times!")
            return
        }

        transactionState = .finalizing

        for (_, finalizationBlock) in finalizationBlocks {
            finalizationBlock(self)
        }

        finalizationBlocks.removeAll()
        transactionState = .finalized
    }

    // MARK: -

    /// Schedule the given block to run when this transaction is finalized.
    ///
    /// - Important
    /// `block` must not capture any database models, as they may no longer be
    /// valid by time the transaction finalizes.
    func addFinalizationBlock(key: String, block: @escaping FinalizationBlock) {
        finalizationBlocks[key] = block
    }

    /// Run the given block synchronously after the transaction is finalized.
    public func addSyncCompletion(block: @escaping () -> Void) {
        completionBlocks.append(block)
    }
}

// MARK: -

public extension LibSignalClient.StoreContext {
    var asTransaction: DBWriteTransaction {
        return self as! DBWriteTransaction
    }
}
