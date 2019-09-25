//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public class BroadcastMediaMessageJobQueue: NSObject, JobQueue {

    public typealias DurableOperationType = BroadcastMediaMessageOperation
    public let requiresInternet: Bool = true
    public static let maxRetries: UInt = 4
    public let jobRecordLabel: String = "BroadcastMediaMessage"

    public var runningOperations: [BroadcastMediaMessageOperation] = []
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

    public func didMarkAsReady(oldJobRecord: OWSBroadcastMediaMessageJobRecord, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "BroadcastMediaMessageJobQueue"
        // TODO - stream uploads from file and raise this limit.
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSBroadcastMediaMessageJobRecord) -> OperationQueue {
        return defaultQueue
    }

    public func buildOperation(jobRecord: OWSBroadcastMediaMessageJobRecord, transaction: SDSAnyReadTransaction) throws -> BroadcastMediaMessageOperation {
        return BroadcastMediaMessageOperation(jobRecord: jobRecord)
    }

    public func add(attachmentIdMap: [String: [String]], transaction: SDSAnyWriteTransaction) {
        let jobRecord = OWSBroadcastMediaMessageJobRecord(attachmentIdMap: attachmentIdMap,
                                                          label: self.jobRecordLabel)
        self.add(jobRecord: jobRecord, transaction: transaction)
    }
}

public class BroadcastMediaMessageOperation: OWSOperation, DurableOperation {
    public typealias JobRecordType = OWSBroadcastMediaMessageJobRecord
    public typealias DurableOperationDelegateType = BroadcastMediaMessageJobQueue
    public var durableOperationDelegate: BroadcastMediaMessageJobQueue?
    public var jobRecord: OWSBroadcastMediaMessageJobRecord
    public var operation: OWSOperation {
        return self
    }

    // MARK: -

    init(jobRecord: OWSBroadcastMediaMessageJobRecord) {
        self.jobRecord = jobRecord
    }

    // MARK: - Dependencies

    var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    // MARK: -

    public override func run() {
        let uploadOperations = jobRecord.attachmentIdMap.keys.map { attachmentId in
            return OWSUploadOperation(attachmentId: attachmentId)
        }

        OWSUploadOperation.uploadQueue.addOperations(uploadOperations, waitUntilFinished: true)
        if let error = (uploadOperations.compactMap { $0.failingError }).first {
            reportError(withUndefinedRetry: error)
            return
        }

        let uploadedAttachments: [TSAttachmentStream] = uploadOperations.compactMap { operation in
            guard let completedUpload = operation.completedUpload else {
                owsFailDebug("completedUpload was unexpectedly nil")
                return nil
            }

            return completedUpload
        }

        var messageIdsToSend: Set<String> = Set()
        databaseStorage.write { transaction in
            // the attachments we've uploaded don't appear in any thread. Once they're
            // uploaded, update the potentially many corresponding attachments in each thread with
            // the details of that upload.
            for uploadedAttachment in uploadedAttachments {
                guard let correspondingAttachments = self.jobRecord.attachmentIdMap[uploadedAttachment.uniqueId] else {
                    owsFailDebug("correspondingAttachments was unexpectedly nil")
                    continue
                }

                let serverId = uploadedAttachment.serverId
                guard let encryptionKey = uploadedAttachment.encryptionKey,
                    let digest = uploadedAttachment.digest,
                    serverId > 0 else {
                        owsFailDebug("uploaded attachment was incomplete")
                        continue
                }

                for correspondingId in correspondingAttachments {
                    guard let correspondingAttachment: TSAttachmentStream = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: correspondingId,
                                                                                                                        transaction: transaction) else {
                        Logger.warn("correspondingAttachment is missing. User has since deleted?")
                        continue
                    }
                    correspondingAttachment.updateAsUploaded(withEncryptionKey: encryptionKey,
                                                             digest: digest,
                                                             serverId: serverId,
                                                             transaction: transaction)

                    guard let albumMessageId = correspondingAttachment.albumMessageId else {
                        owsFailDebug("albumMessageId was unexpectedly nil")
                        continue
                    }
                    messageIdsToSend.insert(albumMessageId)
                }
            }

            for messageId in messageIdsToSend {
                guard let message = TSOutgoingMessage.anyFetchOutgoingMessage(uniqueId: messageId, transaction: transaction) else {
                    owsFailDebug("outgoingMessage was unexpectedly nil")
                    continue
                }

                self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            }
        }

        reportSuccess()
    }
}
