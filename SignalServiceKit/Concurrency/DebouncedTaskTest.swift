//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import Testing

struct DebouncedTaskTest {
    @Test
    func testDebounce() async {
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

        let countOne = await taskOne.value
        let countTwo = await taskTwo.value
        let countThree = await taskThree.value

        #expect(countOne == 1)
        #expect(countTwo == 1)
        #expect(countThree == 1)
        #expect(await debouncedTask.run().value == 2)
    }

    @Test
    func testCancellation() async {
        actor TestActor {
            var allowRunning = false

            func setAllowRunning(_ value: Bool) {
                allowRunning = value
            }
        }

        let testActor = TestActor()

        let debouncedTask = DebouncedTask {
            while await !testActor.allowRunning {
                await Task.yield()
            }

            #expect(throws: CancellationError.self) {
                try Task.checkCancellation()
            }
            #expect(Task.isCancelled)
        }

        let task = debouncedTask.run()
        task.cancel()
        await testActor.setAllowRunning(true)
        await task.value
    }
}
