//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol GroupMemberUpdater {
    func updateRecords(groupThread: TSGroupThread, transaction: DBWriteTransaction)
}

protocol GroupMemberUpdaterTemporaryShims {
    func fetchLatestInteractionTimestamp(
        groupThreadId: String,
        groupMemberAddress: SignalServiceAddress,
        transaction: DBReadTransaction
    ) -> UInt64?

    func didUpdateRecords(groupThreadId: String, transaction: DBWriteTransaction)
}

final class GroupMemberUpdaterImpl: GroupMemberUpdater {
    private let temporaryShims: GroupMemberUpdaterTemporaryShims
    private let groupMemberStore: GroupMemberStore
    private let signalServiceAddressCache: SignalServiceAddressCache

    init(
        temporaryShims: GroupMemberUpdaterTemporaryShims,
        groupMemberStore: GroupMemberStore,
        signalServiceAddressCache: SignalServiceAddressCache
    ) {
        self.temporaryShims = temporaryShims
        self.groupMemberStore = groupMemberStore
        self.signalServiceAddressCache = signalServiceAddressCache
    }

    func updateRecords(groupThread: TSGroupThread, transaction: DBWriteTransaction) {
        let groupThreadId = groupThread.uniqueId

        var groupMembersToRemove = [TSGroupMember]()
        var groupMembersToInsert = [TSGroupMember]()

        // We have to be careful with the order in which we process updates because
        // there are UNIQUE constraints on the group member columns. If we try to
        // update a recipient and some other recipient already has that phone
        // number, the query will fail; this can happen if we're also trying to
        // remove the phone number from that other recipient. To work around
        // potential issues, we issue all DELETEs first, and we implement UPDATEs
        // as a DELETE followed by an INSERT. In the case where a phone number is
        // being claimed from another group member, we DELETE both group members,
        // and then we re-INSERT each group member with the appropriate state.

        // We also may have multiple group members for the same recipient after a
        // merge. In this case, we'll delete the second one we encounter. Because
        // we sort group members based on their most recent interaction, we'll
        // always keep the preferred group member.

        // This is the source of truth; we want to make the TSGroupMember objects
        // on disk match this list of addresses. However, `fullMembers` is decoded
        // from disk, so it may have outdated phone number information. Re-create
        // each address without specifying a phone number to ensure that we only
        // use values contained in the cache.
        var expectedAddresses = Set(groupThread.groupMembership.fullMembers.lazy.map { address in
            address.withNormalizedPhoneNumberAndServiceId(cache: self.signalServiceAddressCache)
        })

        for groupMember in groupMemberStore.sortedFullGroupMembers(in: groupThreadId, tx: transaction) {
            let oldAddress = PersistableDatabaseRecordAddress(
                serviceId: groupMember.serviceId,
                phoneNumber: groupMember.phoneNumber
            )

            let expectedAddress = expectedAddresses.remove(SignalServiceAddress(
                serviceId: oldAddress.serviceId,
                phoneNumber: oldAddress.phoneNumber,
                cache: signalServiceAddressCache
            ))

            let newAddress = NormalizedDatabaseRecordAddress(address: expectedAddress)

            if oldAddress == newAddress?.persistableValue {
                // The value on disk already matches the source of truth; do nothing.
                continue
            }

            // It needs to be removed or updated.
            groupMembersToRemove.append(groupMember)

            if let newAddress {
                // It needs to be updated, so copy fields from the removed group member.
                groupMembersToInsert.append(TSGroupMember(
                    address: newAddress,
                    groupThreadId: groupThreadId,
                    lastInteractionTimestamp: groupMember.lastInteractionTimestamp
                ))
            }
        }

        // Create TSGroupMembers for all the new members.
        for expectedAddress in expectedAddresses {
            guard let newAddress = NormalizedDatabaseRecordAddress(address: expectedAddress) else {
                continue
            }
            // We look up the latest interaction by this user, because they could
            // have been a member of the group previously.
            let latestInteractionTimestamp = temporaryShims.fetchLatestInteractionTimestamp(
                groupThreadId: groupThreadId,
                groupMemberAddress: expectedAddress,
                transaction: transaction
            )
            groupMembersToInsert.append(TSGroupMember(
                address: newAddress,
                groupThreadId: groupThreadId,
                lastInteractionTimestamp: latestInteractionTimestamp ?? 0
            ))
        }

        guard !groupMembersToRemove.isEmpty || !groupMembersToInsert.isEmpty else {
            return
        }

        Logger.info("Updating group members with \(groupMembersToRemove.count) deletion(s) and \(groupMembersToInsert.count) insertion(s)")

        groupMembersToRemove.forEach { groupMemberStore.remove(fullGroupMember: $0, tx: transaction) }
        groupMembersToInsert.forEach { groupMemberStore.insert(fullGroupMember: $0, tx: transaction) }

        temporaryShims.didUpdateRecords(groupThreadId: groupThreadId, transaction: transaction)
    }
}

final class GroupMemberUpdaterTemporaryShimsImpl: GroupMemberUpdaterTemporaryShims {
    func fetchLatestInteractionTimestamp(
        groupThreadId: String,
        groupMemberAddress: SignalServiceAddress,
        transaction: DBReadTransaction
    ) -> UInt64? {
        let interactionFinder = InteractionFinder(threadUniqueId: groupThreadId)
        return interactionFinder.latestInteraction(
            from: groupMemberAddress,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )?.timestamp
    }

    func didUpdateRecords(groupThreadId: String, transaction: DBWriteTransaction) {
        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: TSGroupThread.membershipDidChange, object: groupThreadId)
        }
    }
}
