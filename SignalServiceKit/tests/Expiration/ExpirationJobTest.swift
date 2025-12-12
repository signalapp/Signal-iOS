//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalServiceKit

struct ExpirationJobTest {
    private class TestJob: ExpirationJob<Date> {
        var elements: [Date?] = [nil]
        var deleteCount = 0

        init(
            dateProvider: @escaping DateProvider,
            minIntervalBetweenDeletes: TimeInterval,
            testHooks: TestHooks,
        ) {
            super.init(
                dateProvider: dateProvider,
                db: InMemoryDB(),
                logger: PrefixedLogger(prefix: "[TestExpJob]"),
                minIntervalBetweenDeletes: minIntervalBetweenDeletes,
                testHooks: testHooks,
            )
        }

        func setElements(delays: [TimeInterval]) {
            elements = delays.map { Date().addingTimeInterval($0) }
            elements.append(nil)
        }

        override func nextExpiringElement(tx: DBReadTransaction) -> Date? {
            return elements.first!
        }

        override func expirationDate(ofElement element: Date) -> Date {
            return element
        }

        override func deleteExpiredElement(_ element: Date, tx: DBWriteTransaction) {
            deleteCount += 1
            _ = elements.popFirst()
        }
    }

    @Test
    func testRestarting() async {
        let testIsRunning = AtomicValue(true, lock: .init())
        var shouldRestartJob = true
        let delays: [TimeInterval] = [-0.1, 0.5, 1]

        let job = TestJob(
            dateProvider: { Date() },
            minIntervalBetweenDeletes: 0,
            testHooks: ExpirationJob.TestHooks(
                onWillDelay: { job in
                    let job = job as! TestJob

                    if job.elements.count > 1 {
                        // We've still got stuff to delete.
                    } else if shouldRestartJob {
                        // Add more elements and restart.
                        shouldRestartJob = false
                        job.setElements(delays: delays)
                        job.restart()
                    } else {
                        job.stop()
                    }
                },
                onDidStop: { job in
                    testIsRunning.set(false)
                }
            ),
        )

        job.setElements(delays: delays)
        job.start()
        while testIsRunning.get() {
            await Task.yield()
        }
        #expect(job.deleteCount == 6)
    }

    @Test
    func testStopAndStart() async {
        let testIsRunning = AtomicValue(true, lock: .init())
        var shouldRestartJob = true
        let delays: [TimeInterval] = [-0.1, 0.5, 1]

        let job = TestJob(
            dateProvider: { Date() },
            minIntervalBetweenDeletes: 0,
            testHooks: ExpirationJob.TestHooks(
                onWillDelay: { job in
                    let job = job as! TestJob

                    if job.elements.count > 1 {
                        // We've still got stuff to delete.
                    } else {
                        job.stop()
                    }
                },
                onDidStop: { job in
                    let job = job as! TestJob

                    if shouldRestartJob {
                        // Add more elements and restart.
                        shouldRestartJob = false
                        job.setElements(delays: delays)
                        job.start()
                    } else {
                        testIsRunning.set(false)
                    }
                }
            ),
        )

        job.setElements(delays: delays)
        job.start()
        while testIsRunning.get() {
            await Task.yield()
        }
        #expect(job.deleteCount == 6)
    }
}
