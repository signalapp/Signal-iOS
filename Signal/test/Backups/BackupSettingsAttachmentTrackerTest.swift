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
        let completedExpectedUpdateIndexes: AtomicValue<[UUID: Int]> = AtomicValue(
            [:],
            lock: .init()
        )
        var streamTasks: [Task<Void, Never>] = []

        for updateStream in updateStreams {
            let uuid = UUID()

            completedExpectedUpdateIndexes.update { $0[uuid] = -1 }
            streamTasks.append(Task {
                for await trackedUploadUpdate in updateStream {
                    let nextExpectedUpdateIndex = completedExpectedUpdateIndexes.update {
                        let nextValue = $0[uuid]! + 1
                        $0[uuid] = nextValue
                        return nextValue
                    }
                    let nextExpectedUpdate = expectedUpdates[nextExpectedUpdateIndex]

                    #expect(trackedUploadUpdate == nextExpectedUpdate.update)
                }

                if Task.isCancelled {
                    return
                }

                Issue.record("Finished stream without cancellation!")
            })
        }

        let exhaustedExpectedUpdatesTask = Task {
            var lastCompletedIndex = -1

            while true {
                switch completedExpectedUpdateIndexes.get().values.areAllEqual() {
                case .no:
                    break
                case .yes(let completedIndex) where lastCompletedIndex == completedIndex:
                    break
                case .yes(let completedIndex):
                    if completedIndex == expectedUpdates.count - 1 {
                        streamTasks.forEach { $0.cancel() }
                        return
                    }

                    await expectedUpdates[completedIndex].nextSteps()
                    lastCompletedIndex = completedIndex
                }

                await Task.yield()
            }
        }

        await exhaustedExpectedUpdatesTask.value
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
