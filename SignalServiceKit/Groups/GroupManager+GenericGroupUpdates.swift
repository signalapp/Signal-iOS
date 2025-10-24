//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension GroupManager {
    // Serialize group updates by group ID
    private static let groupUpdateQueues = KeyedConcurrentTaskQueue<GroupIdentifier>(concurrentLimitPerKey: 1)

    private enum GenericGroupUpdateOperation {
        static func run(
            secretParams: GroupSecretParams,
            updateDescription: String,
            changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
        ) async throws {
            do {
                try await Promise.wrapAsync {
                    try await self._run(secretParams: secretParams, changesBlock: changesBlock)
                }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration, description: updateDescription) {
                    return GroupsV2Error.timeout
                }.awaitable()
            } catch {
                Logger.warn("Group update failed: \(error)")
                throw error
            }
        }

        private static func _run(
            secretParams: GroupSecretParams,
            changesBlock: (GroupsV2OutgoingChanges) -> Void
        ) async throws {
            try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()

            try await SSKEnvironment.shared.groupsV2Ref.updateGroupV2(
                secretParams: secretParams,
                changesBlock: changesBlock
            )
        }
    }

    public static func updateGroupV2(
        groupModel: TSGroupModelV2,
        description: String,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) async throws {
        let secretParams = try groupModel.secretParams()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        try await groupUpdateQueues.run(forKey: groupId) {
            try await GenericGroupUpdateOperation.run(
                secretParams: secretParams,
                updateDescription: description,
                changesBlock: changesBlock
            )
        }
    }
}
