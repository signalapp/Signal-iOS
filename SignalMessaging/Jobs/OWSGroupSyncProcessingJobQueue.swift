//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Queue for processing deprecated "groups" sync messages.
///
/// Groups sync messages are a V1 groups concept, and have been deprecated. It's
/// unlikely, but there may be existing job records referring to ancient group
/// sync messages. In that event, this job queue remains to boot them up and
/// immediately fail them.
public class IncomingGroupSyncJobQueue: NSObject, JobQueue {
    public typealias DurableOperationType = IncomingGroupSyncOperation
    public let requiresInternet: Bool = false
    public let isEnabled: Bool = true
    public let jobRecordLabel: String = IncomingGroupSyncJobRecord.defaultLabel

    public var runningOperations = AtomicArray<IncomingGroupSyncOperation>()
    public let isSetup = AtomicBool(false)

    private let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "IncomingGroupSyncJobQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public func didMarkAsReady(oldJobRecord: IncomingGroupSyncJobRecord, transaction: SDSAnyWriteTransaction) {}

    public func operationQueue(jobRecord: IncomingGroupSyncJobRecord) -> OperationQueue {
        return defaultQueue
    }

    public func buildOperation(jobRecord: IncomingGroupSyncJobRecord, transaction: SDSAnyReadTransaction) throws -> IncomingGroupSyncOperation {
        return IncomingGroupSyncOperation(jobRecord: jobRecord)
    }
}

public class IncomingGroupSyncOperation: OWSOperation, DurableOperation {
    public typealias JobRecordType = IncomingGroupSyncJobRecord
    public typealias DurableOperationDelegateType = IncomingGroupSyncJobQueue
    public weak var durableOperationDelegate: IncomingGroupSyncJobQueue?
    public var jobRecord: IncomingGroupSyncJobRecord
    public var operation: OWSOperation { return self }
    public let maxRetries: UInt = 0

    // MARK: -

    init(jobRecord: IncomingGroupSyncJobRecord) {
        self.jobRecord = jobRecord
    }

    public override func run() {
        enum DeprecatedError: Error, IsRetryableProvider {
            case deprecated
            var isRetryableProvider: Bool { false }
        }

        reportError(DeprecatedError.deprecated)
    }

    public override func didSucceed() {
        owsFail("Can never succeed!")
    }

    public override func didReportError(_ error: Error) {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    public override func didFail(error: Error) {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }
}
