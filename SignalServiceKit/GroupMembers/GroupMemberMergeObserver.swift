//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

class GroupMemberMergeObserverImpl: RecipientMergeObserver {
    private let threadStore: ThreadStore
    private let groupMemberUpdater: GroupMemberUpdater
    private let groupMemberStore: GroupMemberStore

    init(
        threadStore: ThreadStore,
        groupMemberUpdater: GroupMemberUpdater,
        groupMemberStore: GroupMemberStore
    ) {
        self.threadStore = threadStore
        self.groupMemberUpdater = groupMemberUpdater
        self.groupMemberStore = groupMemberStore
    }

    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {}

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        var groupThreadIds = [String]()
        if let aci = mergedRecipient.newRecipient.aci {
            groupThreadIds.append(contentsOf: groupMemberStore.groupThreadIds(withFullMember: aci, tx: tx))
        }
        if let phoneNumber = E164(mergedRecipient.newRecipient.phoneNumber) {
            groupThreadIds.append(contentsOf: groupMemberStore.groupThreadIds(withFullMember: phoneNumber, tx: tx))
        }
        if let pni = mergedRecipient.newRecipient.pni {
            groupThreadIds.append(contentsOf: groupMemberStore.groupThreadIds(withFullMember: pni, tx: tx))
        }
        resolveGroupMembers(in: groupThreadIds, tx: tx)
    }

    private func resolveGroupMembers(in groupThreadIds: [String], tx: DBWriteTransaction) {
        for threadId in Set(groupThreadIds) {
            guard let thread = threadStore.fetchGroupThread(uniqueId: threadId, tx: tx) else {
                continue
            }
            mergeV1GroupMembersIfNeeded(in: thread, tx: tx)
            groupMemberUpdater.updateRecords(groupThread: thread, transaction: tx)
        }
    }

    private func mergeV1GroupMembersIfNeeded(in groupThread: TSGroupThread, tx: DBWriteTransaction) {
        let oldGroupModel = groupThread.groupModel
        // In V2 groups, we always have ACIs for full members, so we never need to
        // merge them. For invited group members, we may have PNIs, but we leave
        // the PNI in the list of invitations until it's accepted.
        guard oldGroupModel.groupsVersion == .V1 else {
            return
        }
        let newGroupModel: TSGroupModel
        do {
            // Creating a builder & building it will prune any duplicate addresses.
            newGroupModel = try oldGroupModel.asBuilder.build()
        } catch {
            Logger.warn("Couldn't merge V1 group members.")
            return
        }
        if oldGroupModel == newGroupModel {
            return
        }
        groupThread.update(with: newGroupModel, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
