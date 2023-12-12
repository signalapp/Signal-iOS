//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

final class JobQueueRunnerTest: XCTestCase {
    private var mockDb: MockDB!
    private var jobFinder: MockJobFinder!
    private var jobRunnerFactory: MockJobRunnerFactory!
    private var serialRunner: JobQueueRunner<MockJobFinder, MockJobRunnerFactory>!
    private var concurrentRunner: JobQueueRunner<MockJobFinder, MockJobRunnerFactory>!

    override func setUp() {
        super.setUp()
        mockDb = MockDB()
        jobFinder = MockJobFinder()
        jobRunnerFactory = MockJobRunnerFactory(jobFinder: jobFinder, mockDb: mockDb)
        serialRunner = JobQueueRunner(canExecuteJobsConcurrently: false, db: mockDb, jobFinder: jobFinder, jobRunnerFactory: jobRunnerFactory)
        concurrentRunner = JobQueueRunner(canExecuteJobsConcurrently: true, db: mockDb, jobFinder: jobFinder, jobRunnerFactory: jobRunnerFactory)
    }

    func testConcurrent() async throws {
        let job1 = IncomingContactSyncJobRecord(attachmentId: "A", isCompleteContactSync: true)
        jobFinder.addJob(job1)
        concurrentRunner.addPersistedJob(job1, runner: jobRunnerFactory.buildRunner(retryInterval: 0.001))

        let job2 = IncomingContactSyncJobRecord(attachmentId: "B", isCompleteContactSync: true)
        jobFinder.addJob(job2)
        concurrentRunner.addPersistedJob(job2, runner: jobRunnerFactory.buildRunner(retryInterval: nil))

        concurrentRunner.start(shouldRestartExistingJobs: false)

        while true {
            if jobRunnerFactory.executedJobs.count == 3 {
                break
            }
            try await Task.sleep(nanoseconds: NSEC_PER_USEC)
        }
        try await Task.sleep(nanoseconds: NSEC_PER_USEC)

        let job3 = IncomingContactSyncJobRecord(attachmentId: "C", isCompleteContactSync: true)
        jobFinder.addJob(job3)
        _ = await withCheckedContinuation { continuation in
            concurrentRunner.addPersistedJob(job3, runner: jobRunnerFactory.buildRunner(completionContinuation: continuation))
        }

        let executedJobs = jobRunnerFactory.executedJobs.get()
        XCTAssertEqual(executedJobs.count, 4)
        XCTAssertEqual(executedJobs.filter { $0 == "A" }.count, 2)
        XCTAssertEqual(executedJobs.filter { $0 == "B" }.count, 1)
        XCTAssertEqual(executedJobs[3], "C")
    }

    func testEnqueuedWhileStarting() async throws {
        // Add an old job.
        do {
            let job = IncomingContactSyncJobRecord(attachmentId: "A", isCompleteContactSync: true)
            jobFinder.addJob(job)
        }
        // Add a new job.
        async let result1: JobResult = withCheckedContinuation { continuation in
            let job = IncomingContactSyncJobRecord(attachmentId: "B", isCompleteContactSync: true)
            jobFinder.addJob(job)
            serialRunner.addPersistedJob(job, runner: jobRunnerFactory.buildRunner(completionContinuation: continuation))
        }
        serialRunner.start(shouldRestartExistingJobs: true)
        _ = await result1
        XCTAssertEqual(jobRunnerFactory.executedJobs.get(), ["A", "B"])
        // Add another job that will hopefully restart a stopped queue.
        try await Task.sleep(nanoseconds: NSEC_PER_USEC)
        async let result2: JobResult = withCheckedContinuation { continuation in
            let job = IncomingContactSyncJobRecord(attachmentId: "C", isCompleteContactSync: true)
            jobFinder.addJob(job)
            serialRunner.addPersistedJob(job, runner: jobRunnerFactory.buildRunner(completionContinuation: continuation))
        }
        _ = await result2
        XCTAssertEqual(jobRunnerFactory.executedJobs.get(), ["A", "B", "C"])
    }

    func testRetryWaitingJobs() async throws {
        serialRunner.start(shouldRestartExistingJobs: false)
        let job = IncomingContactSyncJobRecord(attachmentId: "A", isCompleteContactSync: true)
        jobFinder.addJob(job)
        serialRunner.addPersistedJob(job, runner: jobRunnerFactory.buildRunner(completionContinuation: nil, retryInterval: kHourInterval))
        while true {
            serialRunner.retryWaitingJobs()
            if jobRunnerFactory.executedJobs.get() == ["A", "A"] {
                break
            }
            try await Task.sleep(nanoseconds: NSEC_PER_USEC)
        }
    }

    func testRemovedElsewhere() async {
        let job = IncomingContactSyncJobRecord(attachmentId: "A", isCompleteContactSync: true)
        jobFinder.addJob(job)
        mockDb.write { tx in jobFinder.removeJob(job, tx: tx) }
        async let result: JobResult = withCheckedContinuation { continuation in
            serialRunner.addPersistedJob(job, runner: jobRunnerFactory.buildRunner(completionContinuation: continuation))
        }
        serialRunner.start(shouldRestartExistingJobs: false)
        guard case .notFound = await result else { XCTFail("Shouldn't find JobRecord."); return }
    }
}

private class MockJobFinder: JobRecordFinder {
    let jobRecords = AtomicValue<[IncomingContactSyncJobRecord?]>([], lock: AtomicLock())

    func addJob(_ jobRecord: IncomingContactSyncJobRecord) {
        jobRecords.update {
            $0.append(jobRecord)
            jobRecord.id = Int64($0.count)
        }
    }

    func removeJob(_ jobRecord: IncomingContactSyncJobRecord, tx: DBWriteTransaction) {
        jobRecords.update {
            $0[Int(jobRecord.id! - 1)] = nil
        }
    }

    func fetchJob(rowId: JobRecord.RowId, tx: DBReadTransaction) throws -> IncomingContactSyncJobRecord? {
        return jobRecords.update { $0[Int(rowId - 1)] }
    }

    func loadRunnableJobs() async throws -> [IncomingContactSyncJobRecord] {
        return jobRecords.update { $0.compacted() }
    }

    func enumerateJobRecords(transaction: DBReadTransaction, block: (IncomingContactSyncJobRecord, inout Bool) -> Void) throws { fatalError() }
    func enumerateJobRecords(status: JobRecord.Status, transaction: DBReadTransaction, block: (IncomingContactSyncJobRecord, inout Bool) -> Void) throws { fatalError() }
}

private class MockJobRunnerFactory: JobRunnerFactory {
    private let jobFinder: MockJobFinder
    private let mockDb: MockDB

    let executedJobs = AtomicArray<String>(lock: AtomicLock())

    init(jobFinder: MockJobFinder, mockDb: MockDB) {
        self.jobFinder = jobFinder
        self.mockDb = mockDb
    }

    func buildRunner() -> MockJobRunner {
        return buildRunner(completionContinuation: nil, retryInterval: nil)
    }

    func buildRunner(
        completionContinuation: CheckedContinuation<JobResult, Never>? = nil,
        retryInterval: TimeInterval? = nil
    ) -> MockJobRunner {
        return MockJobRunner(
            completionContinuation: completionContinuation,
            executedJobs: executedJobs,
            jobFinder: jobFinder,
            mockDb: mockDb,
            retryInterval: retryInterval
        )
    }
}

private class MockJobRunner: JobRunner {
    let completionContinuation: CheckedContinuation<JobResult, Never>?
    let executedJobs: AtomicArray<String>
    let jobFinder: MockJobFinder
    let mockDb: MockDB
    var retryInterval: TimeInterval?

    init(
        completionContinuation: CheckedContinuation<JobResult, Never>?,
        executedJobs: AtomicArray<String>,
        jobFinder: MockJobFinder,
        mockDb: MockDB,
        retryInterval: TimeInterval?
    ) {
        self.completionContinuation = completionContinuation
        self.executedJobs = executedJobs
        self.jobFinder = jobFinder
        self.mockDb = mockDb
        self.retryInterval = retryInterval
    }

    func runJobAttempt(_ jobRecord: IncomingContactSyncJobRecord) async -> JobAttemptResult {
        executedJobs.append(jobRecord.attachmentId)
        if let retryInterval = self.retryInterval {
            self.retryInterval = nil
            return .retryAfter(retryInterval)
        } else {
            await mockDb.awaitableWrite { tx in self.jobFinder.removeJob(jobRecord, tx: tx) }
            return .finished(.success(()))
        }
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        completionContinuation?.resume(returning: result)
    }
}
