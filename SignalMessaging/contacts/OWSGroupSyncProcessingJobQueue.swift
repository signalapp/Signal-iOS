//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public extension Notification.Name {
    static let IncomingGroupSyncDidComplete = Notification.Name("IncomingGroupSyncDidComplete")
}

@objc(OWSIncomingGroupSyncJobQueue)
public class IncomingGroupSyncJobQueue: NSObject, JobQueue {

    public typealias DurableOperationType = IncomingGroupSyncOperation
    public let requiresInternet: Bool = true
    public let isEnabled: Bool = true
    public static let maxRetries: UInt = 4
    @objc
    public static let jobRecordLabel: String = OWSIncomingGroupSyncJobRecord.defaultLabel
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    public var runningOperations = AtomicArray<IncomingGroupSyncOperation>()
    public var isSetup = AtomicBool(false)

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public func didMarkAsReady(oldJobRecord: OWSIncomingGroupSyncJobRecord, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "IncomingGroupSyncJobQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSIncomingGroupSyncJobRecord) -> OperationQueue {
        return defaultQueue
    }

    public func buildOperation(jobRecord: OWSIncomingGroupSyncJobRecord, transaction: SDSAnyReadTransaction) throws -> IncomingGroupSyncOperation {
        return IncomingGroupSyncOperation(jobRecord: jobRecord)
    }

    @objc
    public func add(attachmentId: String, transaction: SDSAnyWriteTransaction) {
        let jobRecord = OWSIncomingGroupSyncJobRecord(attachmentId: attachmentId,
                                                      label: self.jobRecordLabel)
        self.add(jobRecord: jobRecord, transaction: transaction)
    }
}

public class IncomingGroupSyncOperation: OWSOperation, DurableOperation {
    public typealias JobRecordType = OWSIncomingGroupSyncJobRecord
    public typealias DurableOperationDelegateType = IncomingGroupSyncJobQueue
    public weak var durableOperationDelegate: IncomingGroupSyncJobQueue?
    public var jobRecord: OWSIncomingGroupSyncJobRecord
    public var operation: OWSOperation {
        return self
    }

    public var newThreads: [(threadId: String, sortOrder: UInt32)] = []

    // MARK: -

    init(jobRecord: OWSIncomingGroupSyncJobRecord) {
        self.jobRecord = jobRecord
    }

    // MARK: - Durable Operation Overrides

    public override func run() {
        firstly { () -> Promise<TSAttachmentStream> in
            try self.getAttachmentStream()
        }.done(on: .global()) { attachmentStream in
            self.newThreads = []
            try Bench(title: "processing incoming group sync file") {
                try self.process(attachmentStream: attachmentStream)
            }
            self.databaseStorage.write { transaction in
                guard let attachmentStream = TSAttachmentStream.anyFetch(uniqueId: self.jobRecord.attachmentId, transaction: transaction) else {
                    owsFailDebug("attachmentStream was unexpectedly nil")
                    return
                }
                attachmentStream.anyRemove(transaction: transaction)
            }
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
        NotificationCenter.default.post(name: .IncomingGroupSyncDidComplete, object: self)
    }

    public override func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    public override func didFail(error: Error) {
        Logger.error("failed with error: \(error)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }

    // MARK: - Private

    private func getAttachmentStream() throws -> Promise<TSAttachmentStream> {
        Logger.debug("attachmentId: \(jobRecord.attachmentId)")

        guard let attachment = (databaseStorage.read { transaction in
            return TSAttachment.anyFetch(uniqueId: self.jobRecord.attachmentId, transaction: transaction)
        }) else {
            throw OWSAssertionError("missing attachment")
        }

        switch attachment {
        case let attachmentPointer as TSAttachmentPointer:
            return self.attachmentDownloads.enqueueHeadlessDownloadPromise(attachmentPointer: attachmentPointer)
        case let attachmentStream as TSAttachmentStream:
            return Promise.value(attachmentStream)
        default:
            throw OWSAssertionError("unexpected attachment type: \(attachment)")
        }
    }

    private func process(attachmentStream: TSAttachmentStream) throws {
        guard let fileUrl = attachmentStream.originalMediaURL else {
            throw OWSAssertionError("fileUrl was unexpectedly nil")
        }
        try Data(contentsOf: fileUrl, options: .mappedIfSafe).withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let groupStream = GroupsInputStream(inputStream: inputStream)

                while try processBatch(groupStream: groupStream) {}
            }
        }
    }

    private func processBatch(groupStream: GroupsInputStream) throws -> Bool {
        try autoreleasepool {
            let maxBatchSize = 32
            var count: UInt = 0
            try databaseStorage.write { transaction in
                while count < maxBatchSize,
                      let nextGroup = try groupStream.decodeGroup() {

                    count += 1

                    do {
                        try self.process(groupDetails: nextGroup, transaction: transaction)
                    } catch {
                        if case GroupsV2Error.groupDowngradeNotAllowed = error {
                            Logger.warn("Error: \(error)")
                        } else {
                            owsFailDebug("Error: \(error)")
                        }
                    }
                }
            }
            return count > 0
        }
    }

    private func process(groupDetails: GroupDetails, transaction: SDSAnyWriteTransaction) throws {

        let groupId = groupDetails.groupId
        guard GroupManager.isValidGroupId(groupId, groupsVersion: .V1) else {
            // This would occur if a linked device included a
            // v2 group in a group sync message.
            owsFailDebug("Invalid group id.")
            return
        }

        TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

        // groupUpdateSourceAddress is nil because we don't know
        // who made any changes.
        let groupUpdateSourceAddress: SignalServiceAddress? = nil
        // We only sync v1 groups via group sync messages.

        let disappearingMessageToken = DisappearingMessageToken.token(forProtoExpireTimer: groupDetails.expireTimer)
        let result = try GroupManager.remoteUpsertExistingGroupV1(groupId: groupId,
                                                                  name: groupDetails.name,
                                                                  avatarData: groupDetails.avatarData,
                                                                  members: groupDetails.memberAddresses,
                                                                  disappearingMessageToken: disappearingMessageToken,
                                                                  groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                  infoMessagePolicy: .never,
                                                                  transaction: transaction)

        let groupThread = result.groupThread
        let groupModel = groupThread.groupModel
        let isNewThread = result.action == .inserted
        var groupNeedsUpdate = false

        if isNewThread {
            groupThread.shouldThreadBeVisible = true
            groupNeedsUpdate = true
        }

        if groupDetails.isBlocked {
            if !self.blockingManager.isGroupIdBlocked(groupDetails.groupId, transaction: transaction) {
                self.blockingManager.addBlockedGroup(groupModel: groupModel,
                                                     blockMode: .remote,
                                                     transaction: transaction)
            }
        } else {
            if self.blockingManager.isGroupIdBlocked(groupDetails.groupId, transaction: transaction) {
                self.blockingManager.removeBlockedGroup(groupId: groupDetails.groupId,
                                                        wasLocallyInitiated: false,
                                                        transaction: transaction)
            }
        }

        if isNewThread {
            let inboxSortOrder = groupDetails.inboxSortOrder ?? UInt32.max
            newThreads.append((threadId: groupThread.uniqueId, sortOrder: inboxSortOrder))

            if let isArchived = groupDetails.isArchived, isArchived == true {
                let associatedData = ThreadAssociatedData.fetchOrDefault(for: groupThread, transaction: transaction)
                associatedData.updateWith(isArchived: true, updateStorageService: false, transaction: transaction)
            }
        }

        if groupNeedsUpdate {
            groupThread.anyOverwritingUpdate(transaction: transaction)
        }
    }
}
