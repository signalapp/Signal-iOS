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
     * If we do, and it is immediately followed by a request to join, either within the same TSInfoMessage
     * or in the subsequent one in the same group, we have to update the prior collapsed sequence message
     * to mark it as _not_ the tail (isTail = false). This method is a helper for that, which co-locates the code
     * with the same code for processing incoming group updates during normal app functioning.
     *
     * Note: this method MUST be called before the join request is added to the TSInfoMessage. If the
     * sequence and the final request are on the same message in the backup, first create the message
     * with the first sequence item, then call this, then append the request item.
     *
     * - parameter mostRecentInfoMsg: the most recent info message in the same group. Can be
     * the same info message the new request update belongs to (but this message does not insert the
     * new request, just updates the existing sequence item).
     * - parameter requestingAci: the aci from the subsequent request
     */
    func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        joinRequestFromBackup requestingAci: Aci,
        localIdentifiers: LocalIdentifiers
    )
}

public class GroupUpdateInfoMessageInserterBackupHelperImpl: GroupUpdateInfoMessageInserterBackupHelper {

    public init() {}

    public func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        joinRequestFromBackup requestingAci: Aci,
        localIdentifiers: LocalIdentifiers
    ) {
        GroupUpdateInfoMessageInserterImpl.maybeUpdate(
            mostRecentInfoMsg: mostRecentInfoMsg,
            joinRequestFromBackup: requestingAci,
            localIdentifiers: localIdentifiers
        )
    }
}
