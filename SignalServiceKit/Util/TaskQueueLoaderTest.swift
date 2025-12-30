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
            runner: runner,
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
            runner: runner,
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
            runner: runner,
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
            runner: runner,
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
            runner: runner,
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
            runner: runner,
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
            runner: runner,
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
            runner: runner,
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

    func testSingleTaskCancellation() async throws {
        let runner = MockRunner(numRecords: 100)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner,
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
        // give or take 1 or 2 to let stuff yield.
        XCTAssert(runner.completedTasks.count >= 48)
        XCTAssert(runner.completedTasks.count <= 52)
    }

    func testMultipleTaskCancellation_OnlyOneCancels() async throws {
        let runner = MockRunner(numRecords: 100)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner,
        )

        // Make two tasks that wait on `loadAndRunTasks`.
        // The first will be cancelled after 50 tasks
        // have run; the second will never cancel. By
        // TaskQueueLoader semantics, the runner should
        // never stop running as long as some un-cancelled
        // task is still around.
        var firstTask: Task<Void, Error>!
        var firstTaskContinuation: AsyncStream<Task<Void, Error>>.Continuation! = nil
        let firstTaskStream = AsyncStream<Task<Void, Error>> {
            firstTaskContinuation = $0
        }
        var secondTask: Task<Void, Error>!
        var secondTaskContinuation: AsyncStream<Task<Void, Error>>.Continuation! = nil
        let secondTaskStream = AsyncStream<Task<Void, Error>> {
            secondTaskContinuation = $0
        }
        runner.taskRunner = { id in
            if id == 1 {
                // Make sure both tasks are created before we
                // allow anything to continue
                for await _ in secondTaskStream {}
                for await _ in firstTaskStream {}
                return .success
            } else if id == 50 {
                firstTask.cancel()
                return .success
            } else {
                return .success
            }
        }

        firstTask = Task {
            try await loader.loadAndRunTasks()
        }
        firstTaskContinuation.yield(firstTask)
        firstTaskContinuation.finish()
        secondTask = Task {
            try await loader.loadAndRunTasks()
        }
        secondTaskContinuation.yield(secondTask)
        secondTaskContinuation.finish()
        do {
            try await firstTask.value
        } catch is CancellationError {
            // This is what we want
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        do {
            try await secondTask.value
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let completedTaskCount = runner.completedTasks.count
        // Should have kept going until done!
        XCTAssert(completedTaskCount == 100)
    }

    func testMultipleTaskCancellation_BothCancel() async throws {
        let runner = MockRunner(numRecords: 150)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner,
        )

        // Make two tasks that wait on `loadAndRunTasks`.
        // The first will be cancelled after 50 tasks
        // have run; the second after 100. By
        // TaskQueueLoader semantics, the runner should
        // never stop running as long as some un-cancelled
        // task is still around, so it will only stop
        // after both cancel at 100.
        var firstTask: Task<Void, Error>!
        var firstTaskContinuation: AsyncStream<Task<Void, Error>>.Continuation! = nil
        let firstTaskStream = AsyncStream<Task<Void, Error>> {
            firstTaskContinuation = $0
        }
        var secondTask: Task<Void, Error>!
        var secondTaskContinuation: AsyncStream<Task<Void, Error>>.Continuation! = nil
        let secondTaskStream = AsyncStream<Task<Void, Error>> {
            secondTaskContinuation = $0
        }
        runner.taskRunner = { id in
            if id <= 4 {
                // Make sure both tasks are created before we
                // allow anything to continue
                for await _ in secondTaskStream {}
                for await _ in firstTaskStream {}
                return .success
            } else if id == 50 {
                firstTask.cancel()
                return .success
            } else if id == 100 {
                secondTask.cancel()
                return .success
            } else {
                return .success
            }
        }

        firstTask = Task {
            try await loader.loadAndRunTasks()
        }
        firstTaskContinuation.yield(firstTask)
        firstTaskContinuation.finish()
        secondTask = Task {
            try await loader.loadAndRunTasks()
        }
        secondTaskContinuation.yield(secondTask)
        secondTaskContinuation.finish()
        do {
            try await firstTask.value
        } catch is CancellationError {
            // This is what we want
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        do {
            try await secondTask.value
        } catch is CancellationError {
            // This is what we want
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let completedTaskCount = runner.completedTasks.count
        // Should have cancelled after 100 of them;
        // give or take 1 or 2 to let stuff yield.
        XCTAssert(completedTaskCount >= 98)
        XCTAssert(completedTaskCount <= 102)
    }

    func testMultipleTaskCancellation_NewAwaitAfterCancel() async throws {
        let runner = MockRunner(numRecords: 250)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner,
        )

        // Make two tasks that wait on `loadAndRunTasks`.
        // The first will be cancelled after 50 tasks
        // have run; the second after 100. By
        // TaskQueueLoader semantics, the runner should
        // never stop running as long as some un-cancelled
        // task is still around, so it will only stop
        // after both cancel at 100.
        var tasks = [Task<Void, Error>?]()
        var taskContinuations = [AsyncStream<Void>.Continuation?]()
        var taskContinuationStreams = [AsyncStream<Void>]()
        for i in 0..<3 {
            tasks.append(nil)
            taskContinuations.append(nil)
            taskContinuationStreams.append(AsyncStream<Void> {
                taskContinuations[i] = $0
            })
        }
        runner.taskRunner = { [weak loader] id in
            if id == 0 {
                // Make sure the first two tasks are created before we
                // allow anything to continue
                for await _ in taskContinuationStreams[0] {}
                for await _ in taskContinuationStreams[1] {}
            }
            if id == 50 {
                tasks[0]!.cancel()
            }
            if id == 100 {
                tasks[2] = Task {
                    try await loader!.loadAndRunTasks()
                }
                taskContinuations[2]!.finish()
            }
            if id == 101 {
                for await _ in taskContinuationStreams[2] {}
            }
            if id == 150 {
                tasks[1]!.cancel()
            }
            if id == 200 {
                tasks[2]!.cancel()
            }
            return .success
        }

        tasks[0] = Task {
            try await loader.loadAndRunTasks()
        }
        taskContinuations[0]!.finish()
        tasks[1] = Task {
            try await loader.loadAndRunTasks()
        }
        taskContinuations[1]!.finish()
        for i in 0...2 {
            do {
                try await tasks[i]!.value
            } catch is CancellationError {
                // This is what we want
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        var completedTaskCount = runner.completedTasks.count
        // Should have cancelled after 200 of them;
        // give or take 1 or 2 to let stuff yield.
        XCTAssert(completedTaskCount >= 198)
        XCTAssert(completedTaskCount <= 202)

        // If we now create a new task, it should complete everything.
        try await loader.loadAndRunTasks()
        completedTaskCount = runner.completedTasks.count
        XCTAssert(completedTaskCount <= 250)
    }

    func testCleaningUp_newLoadAndRunTasks() async throws {
        let db = InMemoryDB()

        let store = MockStore(numRecords: 1)
        let runner = MockRunner(store: store)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: db,
            runner: runner,
        )

        var beginDidDrainQueueContinuation: AsyncStream<Void>.Continuation!
        // Awaiting this guy to finish will mean after that point, the first
        // task succeeded and the loader is awaiting didDrainQueue
        let beginDidDrainQueueStream = AsyncStream<Void> {
            beginDidDrainQueueContinuation = $0
        }

        // Finish this guy to release the loader from await didDrainQueue
        var releaseDidDrainQueueContinuation: AsyncStream<Void>.Continuation!
        let releaseDidDrainQueueStream = AsyncStream<Void> {
            releaseDidDrainQueueContinuation = $0
        }

        runner.didDrainQueueBlock = {
            beginDidDrainQueueContinuation.finish()
            for await _ in releaseDidDrainQueueStream {}
        }

        let firstRunTask = Task {
            try await loader.loadAndRunTasks()
        }

        // Ensure we've started the first run, and have put ourselves
        // into the suspended state with didDrainQueue
        for await _ in beginDidDrainQueueStream {}

        // Now, while the queue is in this "cleaning up" state where it
        // is done running and is waiting for didDrainQueue, insert a new
        // record and start up a new loader run.
        store.records.append(MockTaskRecord(id: 2))
        var secondRunContinuation: AsyncStream<Void>.Continuation!
        let secondRunStream = AsyncStream<Void> {
            secondRunContinuation = $0
        }
        let secondRunTask = Task {
            secondRunContinuation.finish()
            try await loader.loadAndRunTasks()
        }
        for await _ in secondRunStream {}

        // Now we can release didDrainQueue for the first run.
        // The second run should start up and pick up the second task
        // record we added.
        releaseDidDrainQueueContinuation.finish()

        try await firstRunTask.value
        try await secondRunTask.value

        let completedTaskCount = runner.completedTasks.count
        XCTAssertEqual(completedTaskCount, 2)
    }

    func testStopWithReason() async throws {
        let runner = MockRunner(numRecords: 10)
        let loader = TaskQueueLoader(
            maxConcurrentTasks: 1,
            dateProvider: { Date() },
            db: InMemoryDB(),
            runner: runner,
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
            runner: runner,
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
        firstRecord.nextRetryTimestamp = now.addingTimeInterval(1).ows_millisecondsSince1970
        let records = [firstRecord] + (1..<10).map(MockTaskRecord.init(id:))
        let runner = MockRunner(store: MockStore(records: records))

        let completedTaskCount = AtomicValue<Int>(0, lock: .init())

        var sleepContinuation: CheckedContinuation<Void, Never>?
        let sleepTask = Task {
            await withCheckedContinuation { continuation in
                sleepContinuation = continuation
            }
        }
        while sleepContinuation == nil {
            await Task.yield()
        }

        let loader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: { now },
            db: InMemoryDB(),
            runner: runner,
            sleep: { nanoseconds in
                XCTAssertEqual(nanoseconds, NSEC_PER_SEC)
                await sleepTask.value
            },
        )

        runner.taskRunner = { id in
            if id == 0 {
                XCTAssertEqual(completedTaskCount.get(), 9)
            } else {
                // The others should all finish before then because
                // they should just run and finish instantly.
                let count = completedTaskCount.map { $0 + 1 }
                if count == 9 {
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
            tx: DBReadTransaction,
        ) throws -> [MockTaskRecord] {
            return Array(records.get().prefix(Int(count)))
        }

        func removeRecord(_ record: MockTaskRecord, tx: DBWriteTransaction) throws {
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

        var didDrainQueueBlock: (() async -> Void)?

        func didDrainQueue() async {
            await didDrainQueueBlock?()
        }
    }
}
