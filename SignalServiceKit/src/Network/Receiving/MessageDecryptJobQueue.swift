//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Durably Decrypt a received signal message enevelope
///
/// The queue's operations (`SSKMessageDecryptOperation`) uses `SSKMessageDecrypt` to decrypt
/// Signal Message envelope data
///
@objc
public class SSKMessageDecryptJobQueue: NSObject, JobQueue {

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.setup()
        }
    }

    // MARK: Dependencies

    // MARK: 

    @objc(enqueueEnvelopeData:)
    public func add(envelopeData: Data) {
        let jobRecord = SSKMessageDecryptJobRecord(envelopeData: envelopeData, label: jobRecordLabel)
        databaseStorage.write { transaction in
            self.add(jobRecord: jobRecord, transaction: transaction)
        }
    }

    // MARK: JobQueue

    public typealias DurableOperationType = SSKMessageDecryptOperation
    public static let jobRecordLabel: String = "SSKMessageDecrypt"
    public static let maxRetries: UInt = 1
    public let requiresInternet: Bool = false
    public var runningOperations: [SSKMessageDecryptOperation] = []

    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    @objc
    public func setup() {
        // Don't decrypt messages in app extensions.
        if !CurrentAppContext().isMainApp {
            return
        }

        // GRDB TODO: Is it really a concern to run the decrypt queue when we're unregistered?
        // If we want this behavior, we should observe registration state changes, and rerun
        // setup whenever it changes.
        // if !self.tsAccountManager.isRegisteredAndReady {
        //     return;
        // }

        defaultSetup()
    }

    public var isSetup: Bool = false

    public func didMarkAsReady(oldJobRecord: SSKMessageDecryptJobRecord, transaction: SDSAnyWriteTransaction) {

    }

    public func buildOperation(jobRecord: SSKMessageDecryptJobRecord, transaction: SDSAnyReadTransaction) throws -> SSKMessageDecryptOperation {
        return SSKMessageDecryptOperation(jobRecord: jobRecord)
    }

    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageDecryptQueue"
        operationQueue.maxConcurrentOperationCount = 1

        return operationQueue
    }()

    public func operationQueue(jobRecord: SSKMessageDecryptJobRecord) -> OperationQueue {
        return defaultQueue
    }
}

public class SSKMessageDecryptOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: SSKMessageDecryptJobRecord

    weak public var durableOperationDelegate: SSKMessageDecryptJobQueue?

    public var operation: OWSOperation {
        return self
    }

    // MARK: Init

    init(jobRecord: SSKMessageDecryptJobRecord) {
        self.jobRecord = jobRecord
        super.init()
    }

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var messageDecrypter: OWSMessageDecrypter {
        return SSKEnvironment.shared.messageDecrypter
    }

    var batchMessageProcessor: OWSBatchMessageProcessor {
        return SSKEnvironment.shared.batchMessageProcessor
    }

    // MARK: OWSOperation

    override public func run() {
        do {
            guard let envelopeData = jobRecord.envelopeData else {
                reportError(OWSErrorMakeAssertionError("envelopeData was unexpectedly nil"))
                return
            }

            let envelope = try SSKProtoEnvelope.parseData(envelopeData)
            let wasReceivedByUD = self.wasReceivedByUD(envelope: envelope)
            messageDecrypter.decryptEnvelope(envelope,
                                             envelopeData: envelopeData,
                                             successBlock: { (result: OWSMessageDecryptResult, transaction: SDSAnyWriteTransaction) in
                                                // We persist the decrypted envelope data in the same transaction within which
                                                // it was decrypted to prevent data loss.  If the new job isn't persisted,
                                                // the session state side effects of its decryption are also rolled back.
                                                //
                                                // NOTE: We use envelopeData from the decrypt result, not job.envelopeData,
                                                // since the envelope may be altered by the decryption process in the UD case.
                                                self.batchMessageProcessor.enqueueEnvelopeData(result.envelopeData,
                                                                                               plaintextData: result.plaintextData,
                                                                                               wasReceivedByUD: wasReceivedByUD,
                                                                                               transaction: transaction)
                                                DispatchQueue.global().async {
                                                    self.reportSuccess()
                                                }
            },
                                             failureBlock: {
                                                // TODO error API's should return specific error
                                                let error = OWSErrorMakeAssertionError("unknown error")
                                                self.reportError(error)
                                            })
        } catch {
            reportError(error)
        }
    }

    override public func didSucceed() {
        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
    }

    override public func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    override public func didFail(error: Error) {
        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }

    // MARK: -

    private func wasReceivedByUD(envelope: SSKProtoEnvelope) -> Bool {
        let hasSenderSource: Bool
        if envelope.hasValidSource {
            hasSenderSource = true
        } else {
            hasSenderSource = false
        }
        return envelope.type == .unidentifiedSender && !hasSenderSource
    }
}
