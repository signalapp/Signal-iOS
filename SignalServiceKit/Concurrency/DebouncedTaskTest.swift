//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import Testing

struct DebouncedTaskTest {
    @Test
    func testDebounce() async throws {
        actor TestActor {
            var allowRunning = false
            var count = 0

            func setAllowRunning() {
                self.allowRunning = true
            }

            func increment() -> Int {
                count += 1
                return count
            }
        }

        let testActor = TestActor()

        let debouncedTask = DebouncedTask { () async -> Int in
            while await !testActor.allowRunning {
                await Task.yield()
            }

            return await testActor.increment()
        }

        let taskOne = debouncedTask.run()
        let taskTwo = debouncedTask.run()
        let taskThree = debouncedTask.run()

        await testActor.setAllowRunning()

        let countOne = try! await taskOne.value
        let countTwo = try! await taskTwo.value
        let countThree = try! await taskThree.value

        #expect(countOne == 1)
        #expect(countTwo == 1)
        #expect(countThree == 1)
        #expect(try await debouncedTask.run().value == 2)
    }

    @Test
    func testFailureThenSuccess() async throws {
        struct ExpectedError: Error {}

        var runResults: [Result<Void, Error>] = [
            .failure(ExpectedError()),
            .success(()),
        ]

        let debouncedTask = DebouncedTask { () async throws in
            guard let runResult = runResults.popFirst() else {
                Issue.record("Missing run result!")
                throw OWSAssertionError("Missing run result!")
            }

            return try runResult.get()
        }

        await #expect(throws: ExpectedError.self) {
            try await debouncedTask.run().value
        }

        try await debouncedTask.run().value
    }

    @Test
    func testIsCurrentlyRunning() async throws {
        actor TestActor {
            var allowRunning = false

            func setAllowRunning() {
                allowRunning = true
            }
        }

        let testActor = TestActor()

        let debouncedTask = DebouncedTask {
            while await !testActor.allowRunning {
                await Task.yield()
            }
        }

        let taskOne = debouncedTask.run()
        #expect(debouncedTask.isCurrentlyRunning() != nil)

        await testActor.setAllowRunning()

        try! await taskOne.value
        #expect(debouncedTask.isCurrentlyRunning() == nil)
    }
}
