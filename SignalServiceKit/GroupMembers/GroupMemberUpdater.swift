//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol GroupMemberUpdater {
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

class GroupMemberUpdaterImpl: GroupMemberUpdater {
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

        // PNI TODO: Ensure that the ACI & PNI are never added to the same group.

        // This is the source of truth; we want to make the TSGroupMember objects
        // on disk match this list of addresses. However, `fullMembers` is decoded
        // from disk, so it may have outdated phone number information. Re-create
        // each address without specifying a phone number to ensure that we only
        // use values contained in the cache.
        var expectedAddresses = Set<SignalServiceAddress>()
        for fullMemberAddress in groupThread.groupMembership.fullMembers {
            if let serviceId = fullMemberAddress.serviceId {
                expectedAddresses.insert(SignalServiceAddress(
                    uuid: serviceId.uuidValue,
                    phoneNumber: nil,
                    cache: signalServiceAddressCache,
                    cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
                ))
            } else {
                expectedAddresses.insert(fullMemberAddress)
            }
        }

        for groupMember in groupMemberStore.sortedFullGroupMembers(in: groupThreadId, tx: transaction) {
            let serviceId = groupMember.serviceId
            let phoneNumber = groupMember.phoneNumber

            let expectedAddress = expectedAddresses.remove(SignalServiceAddress(
                uuid: serviceId?.uuidValue,
                phoneNumber: phoneNumber,
                cache: signalServiceAddressCache,
                cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
            ))

            if let expectedAddress, expectedAddress.serviceId == serviceId, expectedAddress.phoneNumber == phoneNumber {
                // The value on disk already matches the source of truth; do nothing.
                continue
            }

            // It needs to be removed or updated.
            groupMembersToRemove.append(groupMember)

            if let expectedAddress {
                // It needs to be updated, so copy fields from the removed group member.
                groupMembersToInsert.append(TSGroupMember(
                    serviceId: expectedAddress.serviceId,
                    phoneNumber: expectedAddress.phoneNumber,
                    groupThreadId: groupThreadId,
                    lastInteractionTimestamp: groupMember.lastInteractionTimestamp
                ))
            }
        }

        for expectedAddress in expectedAddresses {
            // We look up the latest interaction by this user, because they could
            // have been a member of the group previously.
            let latestInteractionTimestamp = temporaryShims.fetchLatestInteractionTimestamp(
                groupThreadId: groupThreadId,
                groupMemberAddress: expectedAddress,
                transaction: transaction
            )
            groupMembersToInsert.append(TSGroupMember(
                serviceId: expectedAddress.serviceId,
                phoneNumber: expectedAddress.phoneNumber,
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

class GroupMemberUpdaterTemporaryShimsImpl: GroupMemberUpdaterTemporaryShims {
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
        SDSDB.shimOnlyBridge(transaction).addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: TSGroupThread.membershipDidChange, object: groupThreadId)
        }
    }
}
