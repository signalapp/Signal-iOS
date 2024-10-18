//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension GroupManager {
    // Serialize group updates by group ID
    private static let groupUpdateOperationQueues = AtomicValue<[Data: SerialTaskQueue]>([:], lock: .init())

    private static func operationQueue(
        forUpdatingGroup groupModel: TSGroupModel
    ) -> SerialTaskQueue {
        return groupUpdateOperationQueues.update {
            if let operationQueue = $0[groupModel.groupId] {
                return operationQueue
            }
            let operationQueue = SerialTaskQueue()
            $0[groupModel.groupId] = operationQueue
            return operationQueue
        }
    }

    private enum GenericGroupUpdateOperation {
        static func run(
            groupId: Data,
            groupSecretParamsData: Data,
            updateDescription: String,
            changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
        ) async throws -> TSGroupThread {
            do {
                return try await Promise.wrapAsync {
                    try await self._run(groupId: groupId, groupSecretParamsData: groupSecretParamsData, changesBlock: changesBlock)
                }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration, description: updateDescription) {
                    return GroupsV2Error.timeout
                }.awaitable()
            } catch {
                switch error {
                case GroupsV2Error.redundantChange:
                    // From an operation perspective, this is a success!
                    break
                default:
                    owsFailDebug("Group update failed: \(error)")
                }
                throw error
            }
        }

        private static func _run(
            groupId: Data,
            groupSecretParamsData: Data,
            changesBlock: (GroupsV2OutgoingChanges) -> Void
        ) async throws -> TSGroupThread {
            try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()

            return try await SSKEnvironment.shared.groupsV2Ref.updateGroupV2(
                groupId: groupId,
                groupSecretParams: try GroupSecretParams(contents: [UInt8](groupSecretParamsData)),
                changesBlock: changesBlock
            )
        }
    }

    public static func updateGroupV2(
        groupModel: TSGroupModelV2,
        description: String,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) async throws -> TSGroupThread {
        return try await operationQueue(forUpdatingGroup: groupModel).enqueue {
            return try await GenericGroupUpdateOperation.run(
                groupId: groupModel.groupId,
                groupSecretParamsData: groupModel.secretParamsData,
                updateDescription: description,
                changesBlock: changesBlock
            )
        }.value
    }
}
