//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import XCTest
@testable import SignalServiceKit

public class TaskQueueLoaderTest: XCTestCase {

    func testRunAll() async throws {
        let runner = MockRunner(numRecords: 100)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )
        try await loader.loadAndRunTasks()
        // We should have run all tasks
        XCTAssertEqual(runner.completedTasks.count, 100)
        // Each task should only have been run once
        XCTAssertEqual(Set(runner.completedTasks.get()).count, 100)
    }

    func testOneAtATime() async throws {
        let runner = MockRunner(numRecords: 100)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )
        try await loader.loadAndRunTasks()
        // We should have run all tasks
        XCTAssertEqual(runner.completedTasks.count, 100)
        // Each task should only have been run once
        XCTAssertEqual(Set(runner.completedTasks.get()).count, 100)
    }

    func testFewTasks() async throws {
        // Run 4 at a time but only 3 total
        let runner = MockRunner(numRecords: 3)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )
        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 3)
    }

    func testNoTasks() async throws {
        // Should finish right away if there's nothing to run.
        let runner = MockRunner(numRecords: 0)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )
        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 0)
    }

    func testOneTaskDoesntBlockOthers() async throws {
        let runner = MockRunner(numRecords: 100)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        // One single task (the first) will be stuck waiting on the continuation
        var singleTaskContinuation: CheckedContinuation<Void, Never>!
        let singleRecordTask = Task<Void, Never> {
            await withCheckedContinuation { continuation in
                singleTaskContinuation = continuation
            }
        }
        runner.taskRunner = { id in
            if id == 1 {
                await singleRecordTask.value
                return .success
            } else if id == 100 {
                // We should get to the last task regardless; the others
                // should have proceeded 3 at a time.
                // When we reach task 100 we should have finished
                // at most 98 of the tasks (all except number 100 and 1)
                // but we may still be running numbers 98 and 99.
                XCTAssert(runner.completedTasks.count >= 96)
                XCTAssert(runner.completedTasks.count <= 98)
                // Now we unblock the final task so the whole thing can finish.
                singleTaskContinuation.resume()
                return .success
            } else {
                return .success
            }
        }

        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 100)
    }

    func testRetryableError() async throws {
        let runner = MockRunner(numRecords: 10)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        var numFailures = 0
        runner.taskRunner = { id in
            if id == 1, numFailures < 100 {
                // Make the first task fail a few times.
                numFailures += 1
                return .retryableError(MockError())
            } else {
                return .success
            }
        }

        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 10)
        XCTAssertEqual(runner.failedTasks.get(), Array(repeating: 1, count: 100))
    }

    func testUnretryableError() async throws {
        let runner = MockRunner(numRecords: 10)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        runner.taskRunner = { id in
            if id == 1 {
                // Make the first task fail.
                return .unretryableError(MockError())
            } else {
                return .success
            }
        }

        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 9)
        XCTAssertEqual(runner.failedTasks.get(), [1])
    }

    func testRecordCancellation() async throws {
        let runner = MockRunner(numRecords: 10)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        runner.taskRunner = { id in
            if id == 1 {
                // Make the first task cancel.
                return .cancelled
            } else {
                return .success
            }
        }

        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 9)
        XCTAssertEqual(runner.cancelledTasks.get(), [1])
    }

    func testAsyncTaskCancellation() async throws {
        let runner = MockRunner(numRecords: 100)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        var mainTask: Task<Void, Error>!
        runner.taskRunner = { id in
            if id == 50 {
                mainTask.cancel()
                return .success
            } else {
                return .success
            }
        }

        mainTask = Task {
            try await loader.loadAndRunTasks()
        }
        do {
            try await mainTask.value
        } catch is CancellationError {
            // This is what we want
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // Should have cancelled after 50 of them;
        // that could leave us with anywhere from 50 to 53
        // of them completed because we run 4 at a time.
        XCTAssert(runner.completedTasks.count >= 50)
        XCTAssert(runner.completedTasks.count <= 53)
    }

    func testStopWithReason() async throws {
        let runner = MockRunner(numRecords: 10)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        struct MockError: Error {}

        // Don't cancel until we've started one of the tasks.
        var cancelContinuation: CheckedContinuation<Void, Never>?

        // Make the actual tasks spin forever (but allow for cancellation)
        runner.taskRunner = { _ in
            while true {
                do {
                    if cancelContinuation != nil {
                        cancelContinuation?.resume()
                        cancelContinuation = nil
                    }

                    try Task.checkCancellation()
                    await Task.yield()
                } catch {
                    return .cancelled
                }
            }
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                // The tasks run forever, so run in parallel with cancelling.
                taskGroup.addTask {
                    try await loader.loadAndRunTasks()
                }
                taskGroup.addTask {
                    await withCheckedContinuation { continuation in
                        cancelContinuation = continuation
                    }
                    try await loader.stop(reason: MockError())
                }
                try await taskGroup.waitForAll()
            }
        } catch is MockError {
            // This is what we want
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // Should have completed none of them.
        XCTAssertEqual(runner.completedTasks.count, 0)
    }

    func testRunnerItselfStopsThings() async throws {
        let runner = MockRunner(numRecords: 10)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner
        )

        struct MockError: Error {}

        var mainTask: Task<Void, Error>!
        runner.taskRunner = { [weak loader] id in
            if id == 1 {
                try! await loader?.stop(reason: MockError())
                return .success
            } else {
                while true {
                    do {
                        try Task.checkCancellation()
                        await Task.yield()
                    } catch {
                        return .cancelled
                    }
                }
            }
        }

        mainTask = Task {
            try await loader.loadAndRunTasks()
        }
        do {
            try await mainTask.value
        } catch is MockError {
            // This is what we want
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // Should have cancelled after the first; none of the other ever terminate.
        XCTAssertEqual(runner.completedTasks.count, 1)
    }

    func testNextRetryTimestamp() async throws {
        let now = Date()

        var firstRecord = MockTaskRecord(id: 0)
        firstRecord.nextRetryTimestamp = now.addingTimeInterval(0.1).ows_millisecondsSince1970
        let records = [firstRecord] + (1..<10).map(MockTaskRecord.init(id:))
        let runner = MockRunner(store: MockStore(records: records))

        var sleepContinuation: CheckedContinuation<Void, Never>?

        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner,
            sleep: { nanoseconds in
                XCTAssertEqual(nanoseconds, 100 * NSEC_PER_MSEC)
                XCTAssertNil(sleepContinuation)
                await withCheckedContinuation { continuation in
                    sleepContinuation = continuation
                }
            }
        )

        var completedTaskCount = 0
        runner.taskRunner = { id in
            if id == 0 {
                XCTAssertEqual(completedTaskCount, 9)
            } else {
                // The others should all finish before then because
                // they should just run and finish instantly.
                XCTAssert(Date().timeIntervalSince(now) < 0.1)
                completedTaskCount += 1
                if completedTaskCount == 9 {
                    sleepContinuation?.resume()
                }
            }
            return .success
        }

        try await loader.loadAndRunTasks()
        XCTAssertEqual(runner.completedTasks.count, 10)
        XCTAssertEqual(runner.failedTasks.count, 0)
    }

    // MARK: - Mocks

    struct MockError: Error {}

    struct MockTaskRecord: TaskRecord, Equatable {
        let id: Int
        var nextRetryTimestamp: UInt64?

        init(id: Int) {
            self.id = id
            self.nextRetryTimestamp = nil
        }
    }

    class MockStore: TaskRecordStore {

        var records: AtomicArray<MockTaskRecord>

        convenience init(numRecords: Int) {
            self.init(records: (1..<(numRecords + 1)).map(MockTaskRecord.init(id:)))
        }

        init(records: [MockTaskRecord]) {
            self.records = AtomicArray(records, lock: .init())
        }

        func peek(
            count: UInt,
            tx: DBReadTransaction
        ) throws -> [MockTaskRecord] {
            return Array(records.get().prefix(Int(count)))
        }

        func removeRecord(_ record: MockTaskRecord, tx: any DBWriteTransaction) throws {
            records.remove(record)
        }
    }

    final class MockRunner: TaskRecordRunner {
        typealias Store = MockStore

        let store: MockStore

        convenience init(numRecords: Int, doLog: Bool = false) {
            self.init(store: MockStore(numRecords: numRecords))
        }

        init(store: MockStore) {
            self.store = store
        }

        var completedTasks = AtomicArray<Int>(lock: .init())
        var failedTasks = AtomicArray<Int>(lock: .init())
        var cancelledTasks = AtomicArray<Int>(lock: .init())

        var taskRunner: (Int) async -> TaskRecordResult = { _ in
            return .success
        }

        func runTask(record: MockTaskRecord, loader: TaskQueueLoader<MockRunner>) async -> TaskRecordResult {
            return await taskRunner(record.id)
        }

        func didSucceed(record: MockTaskRecord, tx: DBWriteTransaction) throws {
            completedTasks.append(record.id)
        }

        func didFail(record: MockTaskRecord, error: Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            failedTasks.append(record.id)
        }

        func didCancel(record: MockTaskRecord, tx: DBWriteTransaction) throws {
            cancelledTasks.append(record.id)
        }
    }
}
