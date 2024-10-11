//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension GroupManager {
    // Serialize group updates by group ID
    private static var groupUpdateOperationQueues: [Data: OperationQueue] = [:]

    private static func operationQueue(
        forUpdatingGroup groupModel: TSGroupModel
    ) -> OperationQueue {
        if let queue = groupUpdateOperationQueues[groupModel.groupId] {
            return queue
        }

        let newQueue = OperationQueue()
        newQueue.name = "GroupManager-Update"
        newQueue.maxConcurrentOperationCount = 1

        groupUpdateOperationQueues[groupModel.groupId] = newQueue
        return newQueue
    }

    private class GenericGroupUpdateOperation: OWSOperation {
        private let groupId: Data
        private let groupSecretParamsData: Data
        private let updateDescription: String
        private let changesBlock: (GroupsV2OutgoingChanges) -> Void
        private let continuation: CheckedContinuation<TSGroupThread, any Error>

        init(
            groupId: Data,
            groupSecretParamsData: Data,
            updateDescription: String,
            changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void,
            continuation: CheckedContinuation<TSGroupThread, any Error>
        ) {
            self.groupId = groupId
            self.groupSecretParamsData = groupSecretParamsData
            self.updateDescription = updateDescription
            self.changesBlock = changesBlock
            self.continuation = continuation

            super.init()

            self.remainingRetries = 1
        }

        public override func run() {
            Task {
                do {
                    let groupThread = try await Promise.wrapAsync {
                        try await self._run()
                    }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration, description: description) {
                        return GroupsV2Error.timeout
                    }.awaitable()

                    self.reportSuccess()
                    self.continuation.resume(returning: groupThread)
                } catch {
                    switch error {
                    case GroupsV2Error.redundantChange:
                        // From an operation perspective, this is a success!
                        self.reportSuccess()
                        self.continuation.resume(throwing: error)
                    default:
                        owsFailDebug("Group update failed: \(error)")
                        self.reportError(error)
                    }
                }
            }
        }

        private func _run() async throws -> TSGroupThread {
            try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()

            return try await SSKEnvironment.shared.groupsV2Ref.updateGroupV2(
                groupId: self.groupId,
                groupSecretParams: try GroupSecretParams(contents: [UInt8](self.groupSecretParamsData)),
                changesBlock: self.changesBlock
            )
        }

        public override func didFail(error: Error) {
            self.continuation.resume(throwing: error)
        }
    }

    public static func updateGroupV2(
        groupModel: TSGroupModelV2,
        description: String,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) async throws -> TSGroupThread {
        return try await withCheckedThrowingContinuation { continuation in
            let operation = GenericGroupUpdateOperation(
                groupId: groupModel.groupId,
                groupSecretParamsData: groupModel.secretParamsData,
                updateDescription: description,
                changesBlock: changesBlock,
                continuation: continuation
            )
            operationQueue(forUpdatingGroup: groupModel).addOperation(operation)
        }
    }
}
