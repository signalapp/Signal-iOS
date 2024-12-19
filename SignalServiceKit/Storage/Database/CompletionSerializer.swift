//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Executes "sync completion" blocks in order.
///
/// The `addSyncCompletion` method may run blocks enqueued from separate
/// threads in an arbitrary order. This type runs them in order.
///
/// For example, if transactions t1 and t2 enqueue blocks b1 and b2, it's
/// possible for t1 to execute before t2 but b2 to execute before b1. This
/// behavior may be undesired, and this type fixes it.
struct CompletionSerializer {
    /// Identifies `pendingBlocks`. Protected by `tx`'s exclusivity.
    private var blockCounter = 0

    /// Ordered blocks that must be executed.
    private let pendingBlocks = AtomicValue<[(blockNumber: Int, block: () -> Void)]>([], lock: .init())

    mutating func addOrderedSyncCompletion(tx: any DBWriteTransaction, block: @escaping () -> Void) {
        self.blockCounter += 1
        let blockNumber = self.blockCounter

        // Blocks enter this Array in the order they should be executed.
        self.pendingBlocks.update { $0.append((blockNumber, block)) }

        // However, addSyncCompletion blocks are executed in an arbitrary order.
        tx.addSyncCompletion { [pendingBlocks] in
            pendingBlocks.update {
                // Normally, two syncCompletion blocks will execute in order and will each
                // invoke a single pendingBlock. However, if those syncCompletion blocks
                // execute in the opposite order, the second one (now running first) will
                // execute two pendingBlocks, and the first one (now running second) won't
                // execute any pendingBlocks. Note that the pendingBlocks execute in the
                // correct order in both cases, and note also that they execute no later
                // than when their own syncCompletion block executes.
                while let pendingBlock = $0.first, pendingBlock.blockNumber <= blockNumber {
                    pendingBlock.block()
                    $0 = Array($0.dropFirst())
                }
            }
        }
    }
}
