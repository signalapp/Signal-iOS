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
            isDeletingAccount: Bool,
            changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void,
        ) async throws -> [Promise<Void>] {
            do {
                return try await Promise.wrapAsync {
                    return try await self._run(
                        secretParams: secretParams,
                        isDeletingAccount: isDeletingAccount,
                        changesBlock: changesBlock,
                    )
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
            isDeletingAccount: Bool,
            changesBlock: (GroupsV2OutgoingChanges) -> Void,
        ) async throws -> [Promise<Void>] {
            try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()

            return try await SSKEnvironment.shared.groupsV2Ref.updateGroupV2(
                secretParams: secretParams,
                isDeletingAccount: isDeletingAccount,
                changesBlock: changesBlock,
            )
        }
    }

    /// - Returns: A list of Promises for sending the group update message(s).
    /// Each Promise represents sending a message to one or more recipients.
    @discardableResult
    public static func updateGroupV2(
        groupModel: TSGroupModelV2,
        description: String,
        isDeletingAccount: Bool = false,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void,
    ) async throws -> [Promise<Void>] {
        let secretParams = try groupModel.secretParams()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        return try await groupUpdateQueues.run(forKey: groupId) {
            return try await GenericGroupUpdateOperation.run(
                secretParams: secretParams,
                updateDescription: description,
                isDeletingAccount: isDeletingAccount,
                changesBlock: changesBlock,
            )
        }
    }
}
