//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class BroadcastMediaMessageJobQueue: NSObject, JobQueue {

    public typealias DurableOperationType = BroadcastMediaMessageOperation
    public let requiresInternet: Bool = true
    public static let maxRetries: UInt = 4
    @objc
    public static let jobRecordLabel: String = OWSBroadcastMediaMessageJobRecord.defaultLabel
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    public var runningOperations = AtomicArray<BroadcastMediaMessageOperation>()
    public var isSetup = AtomicBool(false)

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
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
    public weak var durableOperationDelegate: BroadcastMediaMessageJobQueue?
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
        do {
            let messagesToSend = try BroadcastMediaUploader.upload(attachmentIdMap: jobRecord.attachmentIdMap)
            databaseStorage.write { transaction in
                for message in messagesToSend {
                    self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                }
            }
        } catch {
            reportError(withUndefinedRetry: error)
        }

        reportSuccess()
    }

    // MARK: -

    public override func didSucceed() {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
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
}

public enum BroadcastMediaUploader {
    static func upload(attachmentIdMap: [String: [String]]) throws -> [TSOutgoingMessage] {
        let observer = NotificationCenter.default.addObserver(
            forName: .attachmentUploadProgress,
            object: nil,
            queue: nil
        ) { notification in
            guard let notificationAttachmentId = notification.userInfo?[kAttachmentUploadAttachmentIDKey] as? String else {
                owsFailDebug("Missing notificationAttachmentId.")
                return
            }
            guard let progress = notification.userInfo?[kAttachmentUploadProgressKey] as? NSNumber else {
                owsFailDebug("Missing progress.")
                return
            }
            guard let correspondingAttachments = attachmentIdMap[notificationAttachmentId] else {
                return
            }
            // Forward upload progress notifications to the corresponding attachments.
            for correspondingId in correspondingAttachments {
                guard correspondingId != notificationAttachmentId else {
                    owsFailDebug("Unexpected attachment id.")
                    continue
                }
                NotificationCenter.default.post(
                    name: .attachmentUploadProgress,
                    object: nil,
                    userInfo: [
                        kAttachmentUploadAttachmentIDKey: correspondingId,
                        kAttachmentUploadProgressKey: progress
                    ]
                )
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let uploadOperations = attachmentIdMap.keys.map { attachmentId in
            // This is only used for media attachments, so we can always use v3.
            return OWSUploadOperation(attachmentId: attachmentId, canUseV3: true)
        }

        OWSUploadOperation.uploadQueue.addOperations(uploadOperations, waitUntilFinished: true)
        if let error = (uploadOperations.compactMap { $0.failingError }).first { throw error }

        let uploadedAttachments: [TSAttachmentStream] = uploadOperations.compactMap { operation in
            guard let completedUpload = operation.completedUpload else {
                owsFailDebug("completedUpload was unexpectedly nil")
                return nil
            }

            return completedUpload
        }

        var messagesToSend = [TSOutgoingMessage]()
        SDSDatabaseStorage.shared.write { transaction in
            var messageIdsToSend: Set<String> = Set()

            // the attachments we've uploaded don't appear in any thread. Once they're
            // uploaded, update the potentially many corresponding attachments in each thread with
            // the details of that upload.
            for uploadedAttachment in uploadedAttachments {
                guard let correspondingAttachments = attachmentIdMap[uploadedAttachment.uniqueId] else {
                    owsFailDebug("correspondingAttachments was unexpectedly nil")
                    continue
                }

                let serverId = uploadedAttachment.serverId
                let cdnKey = uploadedAttachment.cdnKey
                let cdnNumber = uploadedAttachment.cdnNumber
                let uploadTimestamp = uploadedAttachment.uploadTimestamp
                guard let encryptionKey = uploadedAttachment.encryptionKey,
                    let digest = uploadedAttachment.digest,
                    (serverId > 0 || !cdnKey.isEmpty) else {
                        owsFailDebug("uploaded attachment was incomplete")
                        continue
                }
                if uploadTimestamp < 1 {
                    owsFailDebug("Missing uploadTimestamp.")
                }

                for correspondingId in correspondingAttachments {
                    guard let correspondingAttachment = TSAttachmentStream.anyFetchAttachmentStream(
                        uniqueId: correspondingId,
                        transaction: transaction
                    ) else {
                        Logger.warn("correspondingAttachment is missing. User has since deleted?")
                        continue
                    }
                    correspondingAttachment.updateAsUploaded(withEncryptionKey: encryptionKey,
                                                             digest: digest,
                                                             serverId: serverId,
                                                             cdnKey: cdnKey,
                                                             cdnNumber: cdnNumber,
                                                             uploadTimestamp: uploadTimestamp,
                                                             transaction: transaction)

                    guard let albumMessageId = correspondingAttachment.albumMessageId else {
                        owsFailDebug("albumMessageId was unexpectedly nil")
                        continue
                    }
                    messageIdsToSend.insert(albumMessageId)
                }
            }

            messagesToSend = messageIdsToSend.compactMap { messageId in
                guard let message = TSOutgoingMessage.anyFetchOutgoingMessage(
                        uniqueId: messageId,
                        transaction: transaction
                ) else {
                    owsFailDebug("outgoingMessage was unexpectedly nil")
                    return nil
                }
                return message
            }
        }

        return messagesToSend
    }
}
