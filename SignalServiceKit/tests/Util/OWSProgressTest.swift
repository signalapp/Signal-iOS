//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class OWSProgressTest: XCTestCase {

    func testSimpleSourceSink() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source = await sink.addSource(withLabel: "1", unitCount: 100)
                let inputTask = Task {
                    for _ in 0..<10 {
                        await Task.yield()
                        source.incrementCompletedUnitCount(by: 10)
                    }
                }
                await inputTask.await()
            }
        }
        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        XCTAssertLessThanOrEqual(outputs.count, 11)
        XCTAssertEqual(outputs.last, 100)
    }

    func testTwoSources() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source1 = await sink.addSource(withLabel: "1", unitCount: 50)
                let source2 = await sink.addSource(withLabel: "2", unitCount: 50)
                let inputTask1 = Task {
                    for _ in 0..<5 {
                        await Task.yield()
                        source1.incrementCompletedUnitCount(by: 10)
                    }
                }
                let inputTask2 = Task {
                    for _ in 0..<5 {
                        await Task.yield()
                        source2.incrementCompletedUnitCount(by: 10)
                    }
                }
                await inputTask1.await()
                await inputTask2.await()
            }
        }
        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        // initial 0 emission, plus two updates to total unit count, plus 10 updates.
        XCTAssertLessThanOrEqual(outputs.count, 13)
        XCTAssertEqual(outputs.last, 100)
    }

    func testTwoLayers() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source1 = await sink.addSource(withLabel: "1", unitCount: 50)
                let child = await sink.addChild(withLabel: "a", unitCount: 50)
                let source2 = await child.addSource(withLabel: "2", unitCount: 100)
                source1.incrementCompletedUnitCount(by: 50)
                let inputTask = Task {
                    for _ in 0..<10 {
                        await Task.yield()
                        source2.incrementCompletedUnitCount(by: 10)
                    }
                }
                await inputTask.await()
            }
        }
        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        // initial 0 emission, plus two updates to total unit count, plus 10 updates.
        XCTAssertLessThanOrEqual(outputs.count, 13)
        XCTAssertEqual(outputs.last, 100)
    }

    func testMultipleLayers() async {
        // A1 -> A -> root
        let multiplierA1: Float = (1 / 200) * 100
        let unitCountA1: UInt64 = UInt64(ceil(multiplierA1 * 100))
        // B1 -> B -> root
        let multiplierB1: Float = (1 / 200) * 100
        let unitCountB1: UInt64 = UInt64(ceil(multiplierB1 * 50))
        // BZ1 -> BZ -> B -> root
        let multiplierBZ1: Float = (1 / 30) * (50 / 200) * 100
        let unitCountBZ1: UInt64 = UInt64(ceil(multiplierBZ1 * 10))
        // BZ2 -> BZ -> B -> root
        let multiplierBZ2: Float = (1 / 30) * (50 / 200) * 100
        let unitCountBZ2: UInt64 = UInt64(ceil(multiplierBZ2 * 1))
        // C2 -> C -> root
        let multiplierC2: Float = (1 / 11) * 200
        let unitCountC2: UInt64 = UInt64(ceil(multiplierC2 * 5))

        let expectedCompletedUnitCount: UInt64 =
            unitCountA1
            + unitCountB1
            + unitCountBZ1
            + unitCountBZ2
            + unitCountC2

        let outputs: [OWSProgress] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [OWSProgress]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress)
                    if progress.completedUnitCount >= expectedCompletedUnitCount {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let childA = await sink.addChild(withLabel: "A", unitCount: 100)
                let sourceA1 = await childA.addSource(withLabel: "A1", unitCount: 100)
                _ = await childA.addSource(withLabel: "A2", unitCount: 100)
                let childB = await sink.addChild(withLabel: "B", unitCount: 100)
                let sourceB1 = await childB.addSource(withLabel: "B1", unitCount: 50)
                _ = await childB.addSource(withLabel: "B2", unitCount: 100)
                let childBZ = await childB.addChild(withLabel: "BZ", unitCount: 50)
                let sourceBZ1 = await childBZ.addSource(withLabel: "BZ1", unitCount: 10)
                let sourceBZ2 = await childBZ.addSource(withLabel: "BZ2", unitCount: 10)
                _ = await childBZ.addSource(withLabel: "BZ3", unitCount: 10)
                let childC = await sink.addChild(withLabel: "C", unitCount: 200)
                _ = await childC.addSource(withLabel: "C1", unitCount: 1)
                let sourceC2 = await childC.addSource(withLabel: "C2", unitCount: 10)

                // Make partial progress on every layer of the subtree.
                sourceA1.incrementCompletedUnitCount(by: 100)
                sourceB1.incrementCompletedUnitCount(by: 50)
                sourceBZ1.incrementCompletedUnitCount(by: 10)
                sourceBZ2.incrementCompletedUnitCount(by: 1)
                sourceC2.incrementCompletedUnitCount(by: 5)
            }
        }
        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        // initial 0 emission, plus 3 updates to total unit count, plus 5 updates.
        XCTAssertLessThanOrEqual(outputs.count, 9)
        XCTAssertEqual(outputs.last!.completedUnitCount, expectedCompletedUnitCount)
    }

    func testAddToOtherBranchAfterEmitting() async {
        // Say you have your root sink and you add children
        // A and B. You add source A1 to A and B1 to B.
        // You are allowed to add a second source B2 to B
        // after A1 emits but not after B1 emits.
        let outputs: [OWSProgress] = await withCheckedContinuation { percent50Continuation in
            Task {
                var childB: OWSProgressSink?
                let outputs: [OWSProgress] = await withCheckedContinuation { percent25Continuation in
                    Task {
                        var outputs = [OWSProgress]()
                        let sink = OWSProgress.createSink { progress in
                            outputs.append(progress)
                            if progress.percentComplete == 0.25 {
                                percent25Continuation.resume(returning: outputs)
                            }
                            if progress.percentComplete == 0.5 {
                                percent50Continuation.resume(returning: outputs)
                            }
                        }
                        let childA = await sink.addChild(withLabel: "A", unitCount: 100)
                        let sourceA1 = await childA.addSource(withLabel: "A1", unitCount: 100)
                        childB = await sink.addChild(withLabel: "B", unitCount: 100)
                        _ = await childB!.addSource(withLabel: "B1", unitCount: 50)

                        sourceA1.incrementCompletedUnitCount(by: 50)
                    }
                }
                XCTAssertGreaterThanOrEqual(outputs.count, 1)
                XCTAssertEqual(outputs.last!.percentComplete, 0.25)

                XCTAssertNotNil(childB)
                let sourceB2 = await childB?.addSource(withLabel: "B2", unitCount: 50)
                sourceB2?.incrementCompletedUnitCount(by: 50)
            }
        }
        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        XCTAssertEqual(outputs.last!.percentComplete, 0.5)
    }

    func testSourceProgresses() async {
        let expectation1_50p = XCTestExpectation(description: "source1_50p")
        let expectation1_100p = XCTestExpectation(description: "source1_100p")
        let expectationA1_50p = XCTestExpectation(description: "sourceA1_50p")
        let expectationA2_0p = XCTestExpectation(description: "sourceA2_0p")
        let expectationA2_100p = XCTestExpectation(description: "sourceA2_100p")
        let expectationA1_100p = XCTestExpectation(description: "sourcA1_100p")
        let expectation2_0p = XCTestExpectation(description: "source2_0p")
        let expectation2_100p = XCTestExpectation(description: "source2_100p")
        let rootProgress = OWSProgress.createSink { progress in
            guard
                let source1Progress = progress.sourceProgresses["source1"]
            else {
                XCTFail("First progress missing")
                return
            }
            XCTAssertEqual(source1Progress.labels, ["source1"])
            XCTAssertEqual(source1Progress.totalUnitCount, 10)
            guard
                let sourceA1Progress = progress.sourceProgresses["sourceA1"]
            else {
                return
            }
            XCTAssertEqual(sourceA1Progress.labels, ["sinkA", "sourceA1"])
            XCTAssertEqual(sourceA1Progress.totalUnitCount, 100)

            guard source1Progress.percentComplete >= 0.5 else {
                return
            }
            expectation1_50p.fulfill()

            guard source1Progress.isFinished else {
                return
            }
            expectation1_100p.fulfill()

            guard sourceA1Progress.percentComplete >= 0.5 else {
                return
            }
            expectationA1_50p.fulfill()

            guard
                let sourceA2Progress = progress.sourceProgresses["sourceA2"]
            else {
                return
            }
            expectationA2_0p.fulfill()
            XCTAssertEqual(sourceA2Progress.labels, ["sinkA", "sourceA2"])
            XCTAssertEqual(sourceA2Progress.totalUnitCount, 200)

            guard sourceA2Progress.isFinished else {
                return
            }
            expectationA2_100p.fulfill()

            guard sourceA1Progress.isFinished else {
                return
            }
            expectationA1_100p.fulfill()

            guard
                let source2Progress = progress.sourceProgresses["source2"]
            else {
                return
            }
            expectation2_0p.fulfill()
            XCTAssertEqual(source2Progress.labels, ["source2"])
            XCTAssertEqual(source2Progress.totalUnitCount, 20)

            guard source2Progress.isFinished else {
                return
            }
            expectation2_100p.fulfill()
        }

        let source1 = await rootProgress.addSource(withLabel: "source1", unitCount: 10)
        let sinkA = await rootProgress.addChild(withLabel: "sinkA", unitCount: 10)
        let sourceA1 = await sinkA.addSource(withLabel: "sourceA1", unitCount: 100)

        source1.incrementCompletedUnitCount(by: 5)
        await fulfillment(of: [expectation1_50p])

        source1.incrementCompletedUnitCount(by: 5)
        await fulfillment(of: [expectation1_100p])

        sourceA1.incrementCompletedUnitCount(by: 50)
        await fulfillment(of: [expectationA1_50p])

        let sourceA2 = await sinkA.addSource(withLabel: "sourceA2", unitCount: 200)
        await fulfillment(of: [expectationA2_0p])

        sourceA2.incrementCompletedUnitCount(by: 200)
        await fulfillment(of: [expectationA2_100p])

        sourceA1.incrementCompletedUnitCount(by: 50)
        await fulfillment(of: [expectationA1_100p])

        let source2 = await rootProgress.addSource(withLabel: "source2", unitCount: 20)
        await fulfillment(of: [expectation2_0p])

        source2.incrementCompletedUnitCount(by: 20)
        await fulfillment(of: [expectation2_100p])
    }

    func testUpdatePeriodically_estimatedTimeFinishesFirst() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source = await sink.addSource(withLabel: "1", unitCount: 100)
                let inputTask = Task {
                    try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                }
                try await source.updatePeriodically(
                    timeInterval: 0.001,
                    estimatedTimeToCompletion: 50,
                    work: { try await inputTask.value }
                )
            }
        }
        XCTAssertLessThanOrEqual(outputs.count, 52)
        XCTAssertEqual(outputs.last, 100)
    }

    func testUpdatePeriodically_WorkFinishesFirst() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source = await sink.addSource(withLabel: "1", unitCount: 100)
                let inputTask = Task {
                    try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                }
                try await source.updatePeriodically(
                    timeInterval: 0.001,
                    estimatedTimeToCompletion: 200,
                    work: { try await inputTask.value }
                )
            }
        }
        XCTAssertLessThanOrEqual(outputs.count, 102)
        XCTAssertEqual(outputs.last, 100)
    }

    func testUpdatePeriodically_NonThrowing() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source = await sink.addSource(withLabel: "1", unitCount: 100)
                // If the task doesn't throw the updatePeriodically call shouldn't throw either.
                let inputTask = Task {
                    try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                    return "Hello, World!"
                }
                let stringResult = await source.updatePeriodically(
                    timeInterval: 0.001,
                    estimatedTimeToCompletion: 200,
                    work: { await inputTask.value }
                )
                XCTAssertEqual(stringResult, "Hello, World!")
            }
        }
        XCTAssertLessThanOrEqual(outputs.count, 102)
        XCTAssertEqual(outputs.last, 100)
    }

    func testUpdatePeriodically_OptionalResult() async {
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                let source = await sink.addSource(withLabel: "1", unitCount: 100)
                let inputTask: Task<String?, Never> = Task {
                    try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                    return nil
                }
                let stringResult = await source.updatePeriodically(
                    timeInterval: 0.001,
                    estimatedTimeToCompletion: 200,
                    work: { await inputTask.value }
                )
                XCTAssertNil(stringResult)
            }
        }
        XCTAssertLessThanOrEqual(outputs.count, 102)
        XCTAssertEqual(outputs.last, 100)
    }
}
