//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalServiceKit

struct ExpirationJobTest {
    private class TestJob: ExpirationJob<Date> {
        private let dateProvider: DateProvider

        var elements: [Date?] = [nil]
        var deleteCount = 0

        init(
            dateProvider: @escaping DateProvider,
            minIntervalBetweenDeletes: TimeInterval,
        ) {
            self.dateProvider = dateProvider
            super.init(
                dateProvider: dateProvider,
                db: InMemoryDB(),
                logger: PrefixedLogger(prefix: "[TestExpJob]"),
                minIntervalBetweenDeletes: minIntervalBetweenDeletes,
            )
        }

        func setElements(delays: [TimeInterval]) {
            elements = delays.map { dateProvider().addingTimeInterval($0) }
            elements.append(nil)
        }

        var onNextExpiringElement: (() -> Void)?

        override func nextExpiringElement(tx: DBReadTransaction) -> Date? {
            onNextExpiringElement?()
            return elements.first!
        }

        override func expirationDate(ofElement element: Date) -> Date {
            return element
        }

        var onDeleteExpiredElement: (() -> Void)?

        override func deleteExpiredElement(_ element: Date, tx: DBWriteTransaction) {
            deleteCount += 1
            _ = elements.popFirst()
            onDeleteExpiredElement?()
        }
    }

    @Test
    func testRestarting() async throws {
        let now = Date()
        let job = TestJob(
            dateProvider: { now },
            minIntervalBetweenDeletes: 0,
        )
        job.setElements(delays: [-0.1, .year])
        var nextExpiringElementCount = 0
        let didSeeSecondElement = DeferredContinuation<Void>()
        job.onNextExpiringElement = {
            nextExpiringElementCount += 1
            if nextExpiringElementCount == 2 {
                didSeeSecondElement.resume(with: .success(()))
            }
        }
        var deletedElementCount = 0
        let didDeleteSecondElement = DeferredContinuation<Void>()
        job.onDeleteExpiredElement = {
            deletedElementCount += 1
            if deletedElementCount == 2 {
                didDeleteSecondElement.resume(with: .success(()))
            }
        }
        // Start running the job.
        let jobTask = Task {
            _ = try? await job.run()
        }
        // Wait until it observes the second element.
        try await didSeeSecondElement.wait()
        // Add an earlier element.
        job.elements.insert(now.addingTimeInterval(-0.05), at: 0)
        // Restart so that it finds the new element.
        job.restart()
        // Wait until it deletes the second element.
        try await didDeleteSecondElement.wait()
        // Stop the job.
        jobTask.cancel()
        await jobTask.value

        #expect(job.elements == [now.addingTimeInterval(.year), nil])
    }

    @Test
    func testCancel() async {
        let now = Date()
        let job = TestJob(
            dateProvider: { now },
            minIntervalBetweenDeletes: 0,
        )
        job.setElements(delays: [-0.1, .year])
        for _ in 1...2 {
            // Start running the job.
            let jobTask = Task {
                _ = try? await job.run()
            }
            // Stop running the job.
            jobTask.cancel()
            // Make sure it stops.
            await jobTask.value
        }
        // (Then go back and start/stop it again.)

        // It may or may not delete the -0.1 element, but it should never delete
        // the item that expires after a year.
        #expect(job.deleteCount <= 1)
    }
}
