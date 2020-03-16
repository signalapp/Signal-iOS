//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

typealias TestJobRecord = SSKJobRecord

let kJobRecordLabel = "TestJobRecord"
class TestJobQueue: JobQueue {

    // MARK: JobQueue

    typealias DurableOperationType = TestDurableOperation
    var jobRecordLabel: String = kJobRecordLabel
    static var maxRetries: UInt = 1
    public var runningOperations = AtomicArray<TestDurableOperation>()
    var requiresInternet: Bool = false

    func setup() {
        defaultSetup()
    }

    func didMarkAsReady(oldJobRecord: TestJobRecord, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    public var isSetup = AtomicBool(false)

    let operationQueue = OperationQueue()

    func operationQueue(jobRecord: TestJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    func buildOperation(jobRecord: TestJobRecord, transaction: SDSAnyReadTransaction) throws -> TestDurableOperation {
        return TestDurableOperation(jobRecord: jobRecord, jobBlock: self.jobBlock)
    }

    // MARK: 

    var jobBlock: (JobRecordType) -> Void = { _ in /* noop */ }
    init() { }
}

class TestDurableOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    var jobRecord: TestJobRecord

    weak var durableOperationDelegate: TestJobQueue?

    var operation: OWSOperation {
        return self
    }

    // MARK: 

    var jobBlock: (TestJobRecord) -> Void

    init(jobRecord: TestJobRecord, jobBlock: @escaping (TestJobRecord) -> Void) {
        self.jobRecord = jobRecord
        self.jobBlock = jobBlock
    }

    override func run() {
        jobBlock(jobRecord)
        self.reportSuccess()
    }
}

class JobQueueTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: 

    func buildJobRecord() -> TestJobRecord {
        return TestJobRecord(label: kJobRecordLabel)
    }

    // MARK: 

    #if BROKEN_TESTS

    func test_setupMarksInProgressJobsAsReady() {

        let dispatchGroup = DispatchGroup()

        let jobQueue = TestJobQueue()
        let jobRecord1 = buildJobRecord()
        let jobRecord2 = buildJobRecord()
        let jobRecord3 = buildJobRecord()

        var runList: [TestJobRecord] = []

        jobQueue.jobBlock = { jobRecord in
            runList.append(jobRecord)
            dispatchGroup.leave()
        }

        self.write { transaction in
            jobQueue.add(jobRecord: jobRecord1, transaction: transaction)
            jobQueue.add(jobRecord: jobRecord2, transaction: transaction)
            jobQueue.add(jobRecord: jobRecord3, transaction: transaction)
        }
        dispatchGroup.enter()
        dispatchGroup.enter()
        dispatchGroup.enter()

        let finder = AnyJobRecordFinder()
        self.write { transaction in
            XCTAssertEqual(3, finder.allRecords(label: kJobRecordLabel, status: .ready, transaction: transaction).count)
        }

        // start queue
        jobQueue.setup()

        if case .timedOut = dispatchGroup.wait(timeout: .now() + 1.0) {
            XCTFail("timed out waiting for jobs")
        }

        // Normally an operation enqueued for a JobRecord by a JobQueue will mark itself as complete
        // by deleting itself.
        // For testing, the operations enqueued by the TestJobQueue do *not* delete themeselves upon
        // completion, simulating an operation which never compeleted.

        self.write { transaction in
            XCTAssertEqual(0, finder.allRecords(label: kJobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual(3, finder.allRecords(label: kJobRecordLabel, status: .running, transaction: transaction).count)
        }

        // Verify re-queue
        jobQueue.isSetup.set(false)
        jobQueue.setup()

        self.write { transaction in
            XCTAssertEqual(3, finder.allRecords(label: kJobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual(0, finder.allRecords(label: kJobRecordLabel, status: .running, transaction: transaction).count)
        }

        let rerunGroup = DispatchGroup()
        rerunGroup.enter()
        rerunGroup.enter()
        rerunGroup.enter()

        var rerunList: [TestJobRecord] = []
        jobQueue.jobBlock = { jobRecord in
            rerunList.append(jobRecord)
            rerunGroup.leave()
        }

        jobQueue.isSetup.set(true)

        switch rerunGroup.wait(timeout: .now() + 1.0) {
        case .timedOut:
            XCTFail("timed out waiting for retry")
        case .success:
            // verify order maintained on requeue
            XCTAssertEqual([jobRecord1, jobRecord2, jobRecord3].map { $0.uniqueId }, rerunList.map { $0.uniqueId })
        }
    }

    #endif
}
