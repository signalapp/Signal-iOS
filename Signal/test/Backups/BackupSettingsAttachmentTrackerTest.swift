//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import Testing

@testable import Signal

class BackupSettingsAttachmentTrackerTest<Update: Equatable> {
    struct ExpectedUpdate {
        let update: Update?
        let nextSteps: () async -> Void
    }

    actor ExpectedUpdateCompletionTracker {
        private let expectedUpdates: [ExpectedUpdate]
        private var completedExpectedUpdateIndexes: [UUID: Int]

        init(_ expectedUpdates: [ExpectedUpdate]) {
            self.expectedUpdates = expectedUpdates
            self.completedExpectedUpdateIndexes = [:]
        }

        func addNewExpectedUpdateConsumer() -> UUID {
            let uuid = UUID()
            completedExpectedUpdateIndexes[uuid] = -1
            return uuid
        }

        func incrementExpectedUpdate(forConsumer consumer: UUID) async -> ExpectedUpdate {
            let nextIndex = completedExpectedUpdateIndexes[consumer]! + 1
            completedExpectedUpdateIndexes[consumer] = nextIndex

            switch completedExpectedUpdateIndexes.values.areAllEqual() {
            case .no:
                break
            case .yes(let completedIndex):
                await expectedUpdates[completedIndex].nextSteps()
            }

            return expectedUpdates[nextIndex]
        }

        func areAllExpectedUpdatesComplete() -> Bool {
            switch completedExpectedUpdateIndexes.values.areAllEqual() {
            case .no:
                return false
            case .yes(let completedIndex):
                return completedIndex == expectedUpdates.count - 1
            }
        }
    }

    func runTest(
        updateStream: AsyncStream<Update?>,
        expectedUpdates: [ExpectedUpdate]
    ) async {
        await runTest(updateStreams: [updateStream], expectedUpdates: expectedUpdates)
    }

    func runTest(
        updateStreams: [AsyncStream<Update?>],
        expectedUpdates: [ExpectedUpdate]
    ) async {
        let expectedUpdateCompletionTracker = ExpectedUpdateCompletionTracker(expectedUpdates)
        var streamIds: [UUID] = []
        var streamTasks: [Task<Void, Never>] = []

        for _ in updateStreams {
            streamIds.append(await expectedUpdateCompletionTracker.addNewExpectedUpdateConsumer())
        }

        for (updateStream, id) in zip(updateStreams, streamIds) {
            streamTasks.append(Task {
                for await trackedUpdate in updateStream {
                    let nextExpectedUpdate = await expectedUpdateCompletionTracker
                        .incrementExpectedUpdate(forConsumer: id)

                    #expect(trackedUpdate == nextExpectedUpdate.update)
                }

                if Task.isCancelled {
                    return
                }

                Issue.record("Finished stream without cancellation!")
            })
        }

        let expectedUpdatesCompletedTask = Task {
            while await !expectedUpdateCompletionTracker.areAllExpectedUpdatesComplete() {
                await Task.yield()
            }

            streamTasks.forEach { $0.cancel() }
        }

        await expectedUpdatesCompletedTask.value
        for streamTask in streamTasks {
            await streamTask.value
        }
    }
}

// MARK: -

private extension Dictionary.Values where Element: Equatable {
    enum AllEqualResult {
        case yes(Element)
        case no
    }

    func areAllEqual() -> AllEqualResult {
        guard let first else { return .no }

        if allSatisfy({ $0 == first }) {
            return .yes(first)
        }

        return .no
    }
}
