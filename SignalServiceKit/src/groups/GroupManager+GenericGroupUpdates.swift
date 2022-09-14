//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

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
        newQueue.name = "GroupManager.updateQueueForGroup.\(UUID().uuidString)"
        newQueue.maxConcurrentOperationCount = 1

        groupUpdateOperationQueues[groupModel.groupId] = newQueue
        return newQueue
    }

    private class GenericGroupUpdateOperation: OWSOperation {
        private let groupId: Data
        private let groupSecretParamsData: Data
        private let updateDescription: String
        private let changesBlock: (GroupsV2OutgoingChanges) -> Void

        let promise: Promise<TSGroupThread>
        private let future: Future<TSGroupThread>

        init(
            groupId: Data,
            groupSecretParamsData: Data,
            updateDescription: String,
            changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
        ) {
            self.groupId = groupId
            self.groupSecretParamsData = groupSecretParamsData
            self.updateDescription = updateDescription
            self.changesBlock = changesBlock

            let (promise, future) = Promise<TSGroupThread>.pending()
            self.promise = promise
            self.future = future

            super.init()

            self.remainingRetries = 1
        }

        public override func run() {
            firstly {
                GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
            }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
                self.groupsV2Swift.updateGroupV2(
                    groupId: self.groupId,
                    groupSecretParamsData: self.groupSecretParamsData,
                    changesBlock: self.changesBlock
                )
            }.done(on: .global()) { groupThread in
                self.reportSuccess()
                self.future.resolve(groupThread)
            }.timeout(
                seconds: GroupManager.groupUpdateTimeoutDuration,
                description: description
            ) {
                GroupsV2Error.timeout
            }.catch(on: .global()) { error in
                switch error {
                case GroupsV2Error.redundantChange:
                    // From an operation perspective, this is a success!
                    self.reportSuccess()
                    self.future.reject(error)
                default:
                    owsFailDebug("Group update failed: \(error)")
                    self.reportError(error)
                }
            }
        }

        public override func didFail(error: Error) {
            future.reject(error)
        }
    }

    static func updateGroupV2(
        groupModel: TSGroupModelV2,
        description: String,
        changesBlock: @escaping (GroupsV2OutgoingChanges) -> Void
    ) -> Promise<TSGroupThread> {
        let operation = GenericGroupUpdateOperation(
            groupId: groupModel.groupId,
            groupSecretParamsData: groupModel.secretParamsData,
            updateDescription: description,
            changesBlock: changesBlock
        )

        operationQueue(forUpdatingGroup: groupModel).addOperation(operation)

        return operation.promise
    }
}
