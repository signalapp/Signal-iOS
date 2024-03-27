//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol GroupUpdateInfoMessageInserterBackupHelper {

    /**
     * When processing a backup, we may encounter a single group update item
     * representing a collapsed sequence of requests and cancels from the same user
     * (``GroupSequenceOfRequestsAndCancelsUpdate`` proto, which becomes
     * ``TSInfoMessage.PersistableGroupUpdateItem.sequenceOfInviteLinkRequestAndCancels``).
     *
     * If we do, and it is immediately followed by a request to join by the same user in the same group,
     * we have to update the prior collapsed sequence message to mark it as _not_ the tail (isTail = false).
     * This method is a helper for that, which co-locates the code with the same code for processing
     * incoming group updates during normal app functioning.
     *
     * This method handles two cases:
     * 1. The sequence and subsequent request occur in the same TSInfoMessage, meaning they are both
     * in the passed-in updates. In this case it updates the sequence's isTail to false, and returns the
     * modified updates without touching the database.
     * 2. The sequence is in the most recently inserted TSInfoMessage, and the passed-in updates have just
     * the new request from the same user. In this case it updates the most recent TSInfoMessage in the db
     * and returns the same update(s).
     *
     * MUST BE CALLED BEFORE INSERTING THE NEW TSINFOMESSAGE.
     *
     * - parameter updates: the updates pulled from the backup that we are about to generate
     * a new TSInfoMessage for. This method may modify the updates.
     */
    func collapseIfNeeded(
        updates: inout [TSInfoMessage.PersistableGroupUpdateItem],
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    )
}

public class GroupUpdateInfoMessageInserterBackupHelperImpl: GroupUpdateInfoMessageInserterBackupHelper {

    public init() {}

    public func collapseIfNeeded(
        updates: inout [TSInfoMessage.PersistableGroupUpdateItem],
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) {
        return GroupUpdateInfoMessageInserterImpl
            .collapseFromBackupIfNeeded(
                updates: &updates,
                localIdentifiers: localIdentifiers,
                groupThread: groupThread,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
    }
}
