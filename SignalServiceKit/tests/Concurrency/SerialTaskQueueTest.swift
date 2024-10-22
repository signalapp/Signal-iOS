//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import XCTest

@testable import SignalServiceKit

public class SerialTaskQueueTest: XCTestCase {

    func testSerialExecution() async {
        actor TestActor {
            var canExecuteFirstTask = false
            var numExecuted = 0

            func allowFirstTaskExecution() {
                canExecuteFirstTask = true
            }

            func markExecuted() {
                self.numExecuted += 1
            }
        }

        let queue = SerialTaskQueue()
        let testActor = TestActor()

        queue.enqueue(operation: {
            while !(await testActor.canExecuteFirstTask) {
                await Task.yield()
            }
            let numExecuted = await testActor.numExecuted
            XCTAssertEqual(numExecuted, 0)
            await testActor.markExecuted()
        })

        let secondTask = queue.enqueue(operation: {
            let numExecuted = await testActor.numExecuted
            XCTAssertEqual(numExecuted, 1)
            await testActor.markExecuted()
        })

        var numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 0)

        await testActor.allowFirstTaskExecution()

        _  = try! await secondTask.value

        numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 2)

        // A new thing should execute immediately.

        let thirdTask = queue.enqueue(operation: {
            await testActor.markExecuted()
        })

        _ = try! await thirdTask.value

        numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 3)
    }

    /// When an enqueued task throws, the next one should start just fine.
    func testSerialExecutionWithThrows() async {
        struct DummyError: Error {
            static func expect<T>(_ task: Task<T, Error>) async {
                switch await task.result {
                case .success:
                    XCTFail("Expected dummy error, but got success!")
                case .failure(let failure) where failure is DummyError:
                    break
                case .failure(let error):
                    XCTFail("Expected dummy error, but got \(error)")
                }
            }
        }

        actor TestActor {
            var canExecuteFirstTask = false
            var numExecuted = 0

            func allowFirstTaskExecution() {
                canExecuteFirstTask = true
            }

            func markExecuted() {
                self.numExecuted += 1
            }
        }

        let queue = SerialTaskQueue()
        let testActor = TestActor()

        let firstTask = queue.enqueue(operation: {
            while !(await testActor.canExecuteFirstTask) {
                await Task.yield()
            }
            let numExecuted = await testActor.numExecuted
            XCTAssertEqual(numExecuted, 0)
            await testActor.markExecuted()

            throw DummyError()
        })

        let secondTask = queue.enqueue(operation: {
            let numExecuted = await testActor.numExecuted
            XCTAssertEqual(numExecuted, 1)
            await testActor.markExecuted()

            throw DummyError()
        })

        var numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 0)

        await testActor.allowFirstTaskExecution()

        await DummyError.expect(firstTask)
        await DummyError.expect(secondTask)

        numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 2)

        // A new thing should execute immediately.

        let thirdTask = queue.enqueue(operation: {
            await testActor.markExecuted()

            throw DummyError()
        })

        await DummyError.expect(thirdTask)

        numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 3)
    }

    func testCancellation() async throws {
        actor TestActor {
            var canExecuteFirstTask = false
            var numExecuted = 0

            func allowFirstTaskExecution() {
                canExecuteFirstTask = true
            }

            func markExecuted() {
                self.numExecuted += 1
            }
        }

        let queue = SerialTaskQueue()
        let testActor = TestActor()

        let firstTask = queue.enqueue(operation: {
            while !(await testActor.canExecuteFirstTask) {
                try Task.checkCancellation()
                await Task.yield()
            }
            XCTFail("Should have been cancelled!")
        })

        let secondTask = queue.enqueue(operation: {
            try Task.checkCancellation()
            XCTFail("Should have been cancelled!")
        })

        var numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 0)

        // Cancel and then enqueue a new thing.
        let thirdTask = queue.enqueueCancellingPrevious(operation: {
            await testActor.markExecuted()
        })

        _ = try await thirdTask.value

        numExecuted = await testActor.numExecuted
        XCTAssertEqual(numExecuted, 1)

        let firstResult = await firstTask.result
        let secondResult = await secondTask.result
        for result in [firstResult, secondResult] {
            switch result {
            case .success:
                XCTFail("Should have been cancelled!")
            case .failure(let failure):
                XCTAssert(failure is CancellationError)
            }
        }
    }
}
