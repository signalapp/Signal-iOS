//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension Notification.Name {
    static let IncomingGroupSyncDidComplete = Notification.Name("IncomingGroupSyncDidComplete")
}

@objc(OWSIncomingGroupSyncJobQueue)
public class IncomingGroupSyncJobQueue: NSObject, JobQueue {

    public typealias DurableOperationType = IncomingGroupSyncOperation
    public let requiresInternet: Bool = true
    public static let maxRetries: UInt = 4
    @objc
    public static let jobRecordLabel: String = OWSIncomingGroupSyncJobRecord.defaultLabel
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    public var runningOperations: [IncomingGroupSyncOperation] = []
    public var isSetup: Bool = false

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReady {
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

    // MARK: - Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var attachmentDownloads: OWSAttachmentDownloads {
        return SSKEnvironment.shared.attachmentDownloads
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
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
        }.retainUntilComplete()
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
            return self.attachmentDownloads.downloadAttachmentPointer(attachmentPointer)
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

                try databaseStorage.write { transaction in
                    while let nextGroup = try groupStream.decodeGroup() {
                        autoreleasepool {
                            do {
                                try self.process(groupDetails: nextGroup, transaction: transaction)
                            } catch {
                                owsFailDebug("Error: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func process(groupDetails: GroupDetails, transaction: SDSAnyWriteTransaction) throws {

        // GroupsV2 TODO: Eventually we might want to default to V2.
        var groupsVersion: GroupsVersion = .V1
        if let groupsVersionReceived = groupDetails.groupsVersion {
            groupsVersion = groupsVersionReceived
        }
        // GroupsV2 TODO: Set administrators.
        let result = try GroupManager.upsertExistingGroup(members: groupDetails.memberAddresses,
                                                          administrators: [],
                                                          name: groupDetails.name,
                                                          avatarData: groupDetails.avatarData,
                                                          groupId: groupDetails.groupId,
                                                          groupsVersion: groupsVersion,
                                                          groupSecretParamsData: groupDetails.groupSecretParamsData,
                                                          shouldSendMessage: false,
                                                          groupUpdateSourceAddress: nil,
                                                          createInfoMessageForNewGroups: false,
                                                          transaction: transaction)

        let groupThread = result.thread
        let groupModel = groupThread.groupModel
        let isNewThread = result.action == .inserted
        var groupNeedsUpdate = false

        if isNewThread {
            groupThread.shouldThreadBeVisible = true
            groupNeedsUpdate = true
        }

        if let rawSyncedColorName = groupDetails.conversationColorName {
            let conversationColorName = ConversationColorName(rawValue: rawSyncedColorName)
            if conversationColorName != groupThread.conversationColorName {
                groupThread.conversationColorName = conversationColorName
                groupNeedsUpdate = true
            }
        }

        if groupDetails.isBlocked {
            if !self.blockingManager.isGroupIdBlocked(groupDetails.groupId) {
                self.blockingManager.addBlockedGroup(groupModel, wasLocallyInitiated: false, transaction: transaction)
            }
        } else {
            if self.blockingManager.isGroupIdBlocked(groupDetails.groupId) {
                self.blockingManager.removeBlockedGroupId(groupDetails.groupId, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        if isNewThread {
            let inboxSortOrder = groupDetails.inboxSortOrder ?? UInt32.max
            newThreads.append((threadId: groupThread.uniqueId, sortOrder: inboxSortOrder))

            if let isArchived = groupDetails.isArchived, isArchived == true {
                groupThread.archiveThread(with: transaction)
            }
        }

        if groupNeedsUpdate {
            groupThread.anyOverwritingUpdate(transaction: transaction)
        }

        OWSDisappearingMessagesJob.shared().becomeConsistent(withDisappearingDuration: groupDetails.expireTimer,
                                                             thread: groupThread,
                                                             createdByRemoteRecipient: nil,
                                                             createdInExistingGroup: !isNewThread,
                                                             transaction: transaction)
    }
}
