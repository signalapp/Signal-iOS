//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// A request to delete group data as it arrived, before it's checked against
/// the group change it accompanies.
public struct ReceivedGroupDataDeletionRequest {
    let deleteData: SSKProtoGroupContextV2DeleteData
    let senderAci: Aci
}

/// A request, sent alongside a group change, for members to delete their group data.
public enum GroupDataDeletionRequest: Equatable {
    /// The removed members should delete their group data.
    case membersRemoved(Set<Aci>)
    /// Every member should delete their group data because the group ended.
    case groupTerminated

    /// Validates `received` against the change it arrived with. Returns nil
    /// if the request should be ignored.
    init?(
        received: ReceivedGroupDataDeletionRequest,
        changeAuthorAci: Aci?,
        oldGroupMembership: GroupMembership,
        removedAcis: Set<Aci>,
        terminatesGroup: Bool,
    ) {
        let senderAci = received.senderAci
        guard changeAuthorAci == senderAci else {
            Logger.warn("Ignoring data deletion request not sent by the change's author.")
            return nil
        }
        guard oldGroupMembership.isFullMemberAndAdministrator(senderAci) else {
            Logger.warn("Ignoring data deletion request from a non-admin.")
            return nil
        }
        let requestedMemberAcis: Set<Aci>
        do {
            requestedMemberAcis = Set(try received.deleteData.memberAcis.map { try Aci.parseFrom(serviceIdBinary: $0) })
        } catch {
            Logger.warn("Ignoring data deletion request with an invalid ACI.")
            return nil
        }
        // We do a subset check here because the protos technically support removing N people and only
        // requesting that M of them perform the deletion.
        guard requestedMemberAcis.isSubset(of: removedAcis) else {
            Logger.warn("Ignoring data deletion request for members the change doesn't remove.")
            return nil
        }
        if received.deleteData.terminate {
            guard terminatesGroup else {
                Logger.warn("Ignoring data deletion request for a change that doesn't end the group.")
                return nil
            }
            self = .groupTerminated
        } else if !requestedMemberAcis.isEmpty {
            self = .membersRemoved(requestedMemberAcis)
        } else {
            Logger.warn("Ignoring empty data deletion request.")
            return nil
        }
    }
}

/// A manager that can delete group data.
public protocol GroupDataDeletionManager {
    /// Deletes the group's content on this device from before `preservedInteraction`.
    /// Interactions are deleted asynchronously as there may be a lot of them.
    func deleteGroupData(
        groupThread: TSGroupThread,
        preservedInteraction: TSInteraction,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    )
}

final class GroupDataDeletionManagerImpl: GroupDataDeletionManager {
    private let bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue
    private let threadDeletionManager: any ThreadDeletionManager

    init(
        bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        threadDeletionManager: any ThreadDeletionManager,
    ) {
        self.bulkDeleteInteractionJobQueue = bulkDeleteInteractionJobQueue
        self.threadDeletionManager = threadDeletionManager
    }

    func deleteGroupData(
        groupThread: TSGroupThread,
        preservedInteraction: TSInteraction,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        guard
            preservedInteraction.uniqueThreadId == groupThread.uniqueId,
            let preservedInteractionRowId = preservedInteraction.sqliteRowId
        else {
            owsFailDebug("Preserved interaction isn't saved in \(groupThread.logString).")
            return
        }

        Logger.info("Deleting group data in \(groupThread.logString) before interaction \(preservedInteractionRowId).")

        bulkDeleteInteractionJobQueue.addJob(
            anchorMessageRowId: preservedInteractionRowId - 1,
            isFullThreadDelete: false,
            threadUniqueId: groupThread.uniqueId,
            tx: tx,
        )

        threadDeletionManager.removeAssociatedContent(
            thread: groupThread,
            keepingNotificationForMessageId: preservedInteraction.uniqueId,
            localIdentifiers: localIdentifiers,
            tx: tx,
        )
    }
}
