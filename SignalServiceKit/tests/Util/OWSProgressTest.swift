//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class OWSProgressTest: XCTestCase {

    func testSimpleSourceSink() async {
        let (sink, stream) = OWSProgress.createSink()
        Task {
            let source = await sink.addSource(withLabel: "1", unitCount: 100)
            for _ in 0..<10 {
                await Task.yield()
                source.incrementCompletedUnitCount(by: 10)
            }
        }
        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
            if progress.totalUnitCount == 0 {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertNil(progress.progressForChild(label: "1"))
            } else if progress.totalUnitCount == 100 {
                XCTAssertEqual(progress.progressForChild(label: "1")?.totalUnitCount, 100)
                XCTAssertEqual(
                    progress.progressForChild(label: "1")?.completedUnitCount,
                    progress.completedUnitCount,
                )
            } else {
                XCTFail("Unexpected unit count")
            }
        }

        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        XCTAssertLessThanOrEqual(outputs.count, 11)
        XCTAssertEqual(outputs.last, 100)
    }

    func testTwoSources() async {
        let (sink, stream) = OWSProgress.createSink()
        Task {
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

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
            if progress.totalUnitCount == 0 {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertNil(progress.progressForChild(label: "1"))
                XCTAssertNil(progress.progressForChild(label: "2"))
            } else if progress.totalUnitCount == 50 {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertEqual(progress.progressForChild(label: "1")?.totalUnitCount, 50)
                XCTAssertEqual(progress.progressForChild(label: "1")?.completedUnitCount, 0)
                XCTAssertNil(progress.progressForChild(label: "2"))
            } else if progress.totalUnitCount == 100 {
                XCTAssertEqual(progress.progressForChild(label: "1")?.totalUnitCount, 50)
                XCTAssertEqual(progress.progressForChild(label: "2")?.totalUnitCount, 50)
                XCTAssertEqual(
                    progress.progressForChild(label: "1")!.completedUnitCount + progress.progressForChild(label: "2")!.completedUnitCount,
                    progress.completedUnitCount,
                )
            } else {
                XCTFail("Unexpected unit count")
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
        let (sink, stream) = OWSProgress.createSink()
        Task {
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

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
            if progress.totalUnitCount == 0 {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertNil(progress.progressForChild(label: "1"))
                XCTAssertNil(progress.progressForChild(label: "a"))
                XCTAssertNil(progress.progressForChild(label: "2"))
            } else if progress.totalUnitCount == 50 {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertEqual(progress.progressForChild(label: "1")?.totalUnitCount, 50)
                XCTAssertEqual(progress.progressForChild(label: "1")?.completedUnitCount, 0)
                XCTAssertNil(progress.progressForChild(label: "a"))
                XCTAssertNil(progress.progressForChild(label: "2"))
            } else if progress.totalUnitCount == 100 {
                if progress.progressForChild(label: "2") == nil {
                    XCTAssertEqual(progress.completedUnitCount, 0)
                    XCTAssertEqual(progress.progressForChild(label: "1")?.totalUnitCount, 50)
                    XCTAssertEqual(progress.progressForChild(label: "a")?.totalUnitCount, 50)
                } else {
                    XCTAssertEqual(
                        progress.completedUnitCount,
                        progress.progressForChild(label: "1")!.completedUnitCount
                            + progress.progressForChild(label: "a")!.completedUnitCount,
                    )
                    XCTAssertEqual(progress.progressForChild(label: "1")?.totalUnitCount, 50)
                    XCTAssertEqual(progress.progressForChild(label: "a")?.totalUnitCount, 50)
                    XCTAssertEqual(progress.progressForChild(label: "2")?.totalUnitCount, 100)
                    XCTAssertEqual(
                        progress.progressForChild(label: "a")?.completedUnitCount,
                        (progress.progressForChild(label: "2")?.completedUnitCount ?? 0) / 2,
                    )
                }
            } else {
                XCTFail("Unexpected unit count")
            }
        }

        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        // three child node additions, plus 11 updates.
        // some emissions may get debounced.
        XCTAssertLessThanOrEqual(outputs.count, 14)
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

        let (sink, stream) = OWSProgress.createSink()
        Task {
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

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
            if progress.completedUnitCount >= expectedCompletedUnitCount {
                break
            }
        }

        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        // initial 0 emission, plus 13 updates to nodes, plus 5 updates.
        XCTAssertLessThanOrEqual(outputs.count, 19)
        XCTAssertEqual(outputs.last!, expectedCompletedUnitCount)
    }

    func testAddToOtherBranchAfterEmitting() async {
        // Say you have your root sink and you add children
        // A and B. You add source A1 to A and B1 to B.
        // You are allowed to add a second source B2 to B
        // after A1 emits but not after B1 emits.
        let (sink, stream) = OWSProgress.createSink()
        let childA = await sink.addChild(withLabel: "A", unitCount: 100)
        let sourceA1 = await childA.addSource(withLabel: "A1", unitCount: 100)
        let childB = await sink.addChild(withLabel: "B", unitCount: 100)
        _ = await childB.addSource(withLabel: "B1", unitCount: 50)

        Task {
            sourceA1.incrementCompletedUnitCount(by: 50)
        }

        var outputs = [Float]()
        for await progress in stream {
            outputs.append(progress.percentComplete)
            if progress.progressForChild(label: "A") == nil {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertEqual(progress.totalUnitCount, 0)
            } else if progress.progressForChild(label: "A1") == nil {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertEqual(progress.totalUnitCount, 100)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
            } else if progress.progressForChild(label: "B") == nil {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertEqual(progress.totalUnitCount, 100)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A1",
                        parentLabel: "A",
                    ),
                )
            } else if progress.progressForChild(label: "B1") == nil {
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertEqual(progress.totalUnitCount, 200)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A1",
                        parentLabel: "A",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "B",
                        parentLabel: nil,
                    ),
                )
            } else if progress.completedUnitCount == 0 {
                XCTAssertEqual(progress.totalUnitCount, 200)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "A1",
                        parentLabel: "A",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "B",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 50,
                        label: "B1",
                        parentLabel: "B",
                    ),
                )
            } else if progress.completedUnitCount == 50 {
                XCTAssertEqual(progress.totalUnitCount, 200)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A1",
                        parentLabel: "A",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "B",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 50,
                        label: "B1",
                        parentLabel: "B",
                    ),
                )
                break
            } else {
                XCTFail("Unexpected progress update")
            }
        }

        XCTAssertGreaterThanOrEqual(outputs.count, 1)

        Task {
            let sourceB2 = await childB.addSource(withLabel: "B2", unitCount: 50)
            sourceB2.incrementCompletedUnitCount(by: 50)
        }

        for await progress in stream {
            outputs.append(progress.percentComplete)
            if progress.completedUnitCount == 50 {
                XCTAssertEqual(progress.totalUnitCount, 200)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A1",
                        parentLabel: "A",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 100,
                        label: "B",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 50,
                        label: "B1",
                        parentLabel: "B",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B2"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 50,
                        label: "B2",
                        parentLabel: "B",
                    ),
                )
            } else if progress.completedUnitCount == 100 {
                XCTAssertEqual(progress.totalUnitCount, 200)
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A1",
                        parentLabel: "A",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "B",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 50,
                        label: "B1",
                        parentLabel: "B",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B2"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 50,
                        label: "B2",
                        parentLabel: "B",
                    ),
                )
                break
            } else {
                XCTFail("Unexpected progress update")
            }
        }

        // Emissions can get debounced, so we can't guarantee
        // anything about them except that theres a first and last.
        XCTAssertGreaterThanOrEqual(outputs.count, 1)
        XCTAssertEqual(outputs.last!, 0.5)
    }

    func testRestartLabel() async {
        // Add 1, A, B, C to the root,
        // then 2 to A,
        // 3, 4, D to B,
        // 5 to C
        // 6, E to D.
        // Make some progres on all of them, then...
        // * "reset" 1 by re-adding it to the root
        // * "reset" 3 by re-adding it to B.
        // * "reset" C and all its children by re-adding it to the root
        // * "reset" D and all its children by re-adding it to C
        let (sink, stream) = OWSProgress.createSink()
        var source1 = await sink.addSource(withLabel: "1", unitCount: 100)
        let childA = await sink.addChild(withLabel: "A", unitCount: 100)
        let childB = await sink.addChild(withLabel: "B", unitCount: 100)
        var childC = await sink.addChild(withLabel: "C", unitCount: 100)
        let source2 = await childA.addSource(withLabel: "2", unitCount: 100)
        var source3 = await childB.addSource(withLabel: "3", unitCount: 100)
        let source4 = await childB.addSource(withLabel: "4", unitCount: 100)
        var childD = await childB.addChild(withLabel: "D", unitCount: 100)
        let source5 = await childC.addSource(withLabel: "5", unitCount: 100)
        let source6 = await childD.addSource(withLabel: "6", unitCount: 100)
        _ = await childD.addChild(withLabel: "E", unitCount: 0)

        // Complete everything by 50%
        source1.incrementCompletedUnitCount(by: 50)
        source2.incrementCompletedUnitCount(by: 50)
        source3.incrementCompletedUnitCount(by: 50)
        source4.incrementCompletedUnitCount(by: 50)
        source5.incrementCompletedUnitCount(by: 50)
        source6.incrementCompletedUnitCount(by: 50)

        for await progress in stream {
            // Wait to get all the updates from the setup we did.
            if progress.completedUnitCount == 200 {
                XCTAssertEqual(progress.totalUnitCount, 400)
                XCTAssertEqual(
                    progress.progressForChild(label: "1"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "1",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "A"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "A",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "2"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "2",
                        parentLabel: "A",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "B"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "B",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "3"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "3",
                        parentLabel: "B",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "4"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "4",
                        parentLabel: "B",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "D"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "D",
                        parentLabel: "B",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "C"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "C",
                        parentLabel: nil,
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "5"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "5",
                        parentLabel: "C",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "6"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 50,
                        totalUnitCount: 100,
                        label: "6",
                        parentLabel: "D",
                    ),
                )
                XCTAssertEqual(
                    progress.progressForChild(label: "E"),
                    OWSProgress.ChildProgress(
                        completedUnitCount: 0,
                        totalUnitCount: 0,
                        label: "E",
                        parentLabel: "D",
                    ),
                )
                break
            }
        }

        // Now "reset" source1, and use a new unit count to boot
        let oldSource1 = source1
        source1 = await sink.addSource(withLabel: "1", unitCount: 200)
        for await progress in stream {
            XCTAssertEqual(progress.completedUnitCount, 150)
            XCTAssertEqual(progress.totalUnitCount, 500)
            XCTAssertEqual(
                progress.progressForChild(label: "1"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "1",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "A"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "A",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "2"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "2",
                    parentLabel: "A",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "B"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "B",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "3"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "3",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "4"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "4",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "D"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "D",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "C"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "C",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "5"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "5",
                    parentLabel: "C",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "6"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "6",
                    parentLabel: "D",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "E"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 0,
                    label: "E",
                    parentLabel: "D",
                ),
            )
            break
        }

        // Updating old source 1 should do nothing (we're expecting exactly one
        // update below)
        oldSource1.incrementCompletedUnitCount(by: 50)

        // Now reset source 3.
        let oldSource3 = source3
        source3 = await childB.addSource(withLabel: "3", unitCount: 100)
        for await progress in stream {
            XCTAssertEqual(progress.completedUnitCount, 134)
            XCTAssertEqual(progress.totalUnitCount, 500)
            XCTAssertEqual(
                progress.progressForChild(label: "1"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "1",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "A"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "A",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "2"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "2",
                    parentLabel: "A",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "B"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 34,
                    totalUnitCount: 100,
                    label: "B",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "3"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 100,
                    label: "3",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "4"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "4",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "D"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "D",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "C"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "C",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "5"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "5",
                    parentLabel: "C",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "6"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "6",
                    parentLabel: "D",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "E"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 0,
                    label: "E",
                    parentLabel: "D",
                ),
            )
            break
        }

        // Updating old source 3 should do nothing (we're expecting exactly one
        // update below)
        oldSource3.incrementCompletedUnitCount(by: 50)

        // Now reset child C
        let oldSource5 = source5
        childC = await sink.addChild(withLabel: "C", unitCount: 200)
        for await progress in stream {
            XCTAssertEqual(progress.completedUnitCount, 84)
            XCTAssertEqual(progress.totalUnitCount, 600)
            XCTAssertEqual(
                progress.progressForChild(label: "1"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "1",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "A"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "A",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "2"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "2",
                    parentLabel: "A",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "B"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 34,
                    totalUnitCount: 100,
                    label: "B",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "3"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 100,
                    label: "3",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "4"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "4",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "D"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "D",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "C"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "C",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "6"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "6",
                    parentLabel: "D",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "E"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 0,
                    label: "E",
                    parentLabel: "D",
                ),
            )
            break
        }

        // Updating old source 5 (child of C) should do nothing (we're expecting exactly one
        // update below)
        oldSource5.incrementCompletedUnitCount(by: 50)

        // Now reset D
        childD = await childB.addChild(withLabel: "D", unitCount: 100)
        for await progress in stream {
            XCTAssertEqual(progress.completedUnitCount, 67)
            XCTAssertEqual(progress.totalUnitCount, 600)
            XCTAssertEqual(
                progress.progressForChild(label: "1"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "1",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "A"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "A",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "2"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "2",
                    parentLabel: "A",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "B"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 17,
                    totalUnitCount: 100,
                    label: "B",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "3"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 100,
                    label: "3",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "4"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "4",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "D"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 100,
                    label: "D",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "C"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "C",
                    parentLabel: nil,
                ),
            )
            break
        }

        // We should be allowed to add a new source with the same
        // label (1) at another layer of the tree (to D)
        await childD.addSource(withLabel: "1", unitCount: 100)
            .incrementCompletedUnitCount(by: 100)
        for await progress in stream {
            if progress.completedUnitCount == 67 {
                // skip the first update
                continue
            }
            XCTAssertEqual(progress.completedUnitCount, 100)
            XCTAssertEqual(progress.totalUnitCount, 600)
            let progressesFor1 = progress.progressesForAllChildren(withLabel: "1")
            XCTAssertEqual(progressesFor1.count, 2)
            XCTAssert(progressesFor1.contains(
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "1",
                    parentLabel: nil,
                ),
            ))
            XCTAssert(progressesFor1.contains(
                OWSProgress.ChildProgress(
                    completedUnitCount: 100,
                    totalUnitCount: 100,
                    label: "1",
                    parentLabel: "D",
                ),
            ))
            XCTAssertEqual(
                progress.progressForChild(label: "A"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "A",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "2"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "2",
                    parentLabel: "A",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "B"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "B",
                    parentLabel: nil,
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "3"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 100,
                    label: "3",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "4"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 50,
                    totalUnitCount: 100,
                    label: "4",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "D"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 100,
                    totalUnitCount: 100,
                    label: "D",
                    parentLabel: "B",
                ),
            )
            XCTAssertEqual(
                progress.progressForChild(label: "C"),
                OWSProgress.ChildProgress(
                    completedUnitCount: 0,
                    totalUnitCount: 200,
                    label: "C",
                    parentLabel: nil,
                ),
            )
            break
        }
    }

    func testChildProgresses() async {
        let (rootProgress, stream) = OWSProgress.createSink()

        func wait(label: String, percent: Float) async {
            for await progress in stream {
                if progress.progressForChild(label: label)?.percentComplete == percent {
                    break
                }
            }
        }

        let source1 = await rootProgress.addSource(withLabel: "source1", unitCount: 10)
        let sinkA = await rootProgress.addChild(withLabel: "sinkA", unitCount: 10)
        let sourceA1 = await sinkA.addSource(withLabel: "sourceA1", unitCount: 100)

        source1.incrementCompletedUnitCount(by: 5)
        await wait(label: "source1", percent: 0.5)

        source1.incrementCompletedUnitCount(by: 5)
        await wait(label: "source1", percent: 1)

        sourceA1.incrementCompletedUnitCount(by: 50)
        await wait(label: "sourceA1", percent: 0.5)

        let sourceA2 = await sinkA.addSource(withLabel: "sourceA2", unitCount: 200)
        await wait(label: "sourceA2", percent: 0)

        sourceA2.incrementCompletedUnitCount(by: 200)
        await wait(label: "sourceA2", percent: 1)

        sourceA1.incrementCompletedUnitCount(by: 50)
        await wait(label: "sourceA1", percent: 1)

        let source2 = await rootProgress.addSource(withLabel: "source2", unitCount: 20)
        await wait(label: "source2", percent: 0)

        source2.incrementCompletedUnitCount(by: 20)
        await wait(label: "source2", percent: 1)
    }

    func testUpdatePeriodically_estimatedTimeFinishesFirst() async {
        let (sink, stream) = OWSProgress.createSink()
        Task {
            let source = await sink.addSource(withLabel: "1", unitCount: 100)
            let inputTask = Task {
                try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            }
            try await source.updatePeriodically(
                timeInterval: 0.001,
                estimatedTimeToCompletion: 50,
                work: { try await inputTask.value },
            )
        }

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
        }

        XCTAssertLessThanOrEqual(outputs.count, 52)
        XCTAssertEqual(outputs.last, 100)
    }

    func testUpdatePeriodically_WorkFinishesFirst() async {
        let (sink, stream) = OWSProgress.createSink()
        Task {
            let source = await sink.addSource(withLabel: "1", unitCount: 100)
            let inputTask = Task {
                try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            }
            try await source.updatePeriodically(
                timeInterval: 0.001,
                estimatedTimeToCompletion: 200,
                work: { try await inputTask.value },
            )
        }

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
        }

        XCTAssertLessThanOrEqual(outputs.count, 102)
        XCTAssertEqual(outputs.last, 100)
    }

    func testUpdatePeriodically_NonThrowing() async {
        let (sink, stream) = OWSProgress.createSink()
        Task {
            let source = await sink.addSource(withLabel: "1", unitCount: 100)
            // If the task doesn't throw the updatePeriodically call shouldn't throw either.
            let inputTask = Task {
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                return "Hello, World!"
            }
            let stringResult = await source.updatePeriodically(
                timeInterval: 0.001,
                estimatedTimeToCompletion: 200,
                work: { await inputTask.value },
            )
            XCTAssertEqual(stringResult, "Hello, World!")
        }

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
        }

        XCTAssertLessThanOrEqual(outputs.count, 102)
        XCTAssertEqual(outputs.last, 100)
    }

    func testUpdatePeriodically_OptionalResult() async {
        let (sink, stream) = OWSProgress.createSink()
        Task {
            let source = await sink.addSource(withLabel: "1", unitCount: 100)
            let inputTask: Task<String?, Never> = Task {
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                return nil
            }
            let stringResult = await source.updatePeriodically(
                timeInterval: 0.001,
                estimatedTimeToCompletion: 200,
                work: { await inputTask.value },
            )
            XCTAssertNil(stringResult)
        }

        var outputs = [UInt64]()
        for await progress in stream {
            outputs.append(progress.completedUnitCount)
        }

        XCTAssertLessThanOrEqual(outputs.count, 102)
        XCTAssertEqual(outputs.last, 100)
    }

    func testSimpleSourceSink_callback() async {
        var sinkRef: OWSProgressSink?
        let outputs: [UInt64] = await withCheckedContinuation { outputsContinuation in
            Task {
                var outputs = [UInt64]()
                let sink = OWSProgress.createSink { progress in
                    outputs.append(progress.completedUnitCount)
                    if progress.isFinished {
                        outputsContinuation.resume(returning: outputs)
                    }
                }
                sinkRef = sink
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
        XCTAssertNotNil(sinkRef)
    }

    // MARK: - Zero Unit Counts

    func testZeroUnitCount_sourceOnRoot() async {
        let (sink, stream) = OWSProgress.createSink()
        let source = await sink.addSource(withLabel: "source", unitCount: 0)
        // Incrementing is irrelevant.
        source.incrementCompletedUnitCount(by: 0)
        source.incrementCompletedUnitCount(by: 100)
        // Should complete after a single progress update.
        var numUpdates = 0
        for await progress in stream {
            numUpdates += 1
            switch numUpdates {
            case 1:
                XCTAssertEqual(progress.percentComplete, 1)
                XCTAssertEqual(progress.totalUnitCount, 0)
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssert(progress.isFinished)
            default:
                XCTFail("Unexpected update")
            }
        }
    }

    func testZeroUnitCount_childOnRoot() async {
        let (sink, stream) = OWSProgress.createSink()
        let child = await sink.addChild(withLabel: "child", unitCount: 0)
        let source = await child.addSource(withLabel: "source", unitCount: 100)
        // Incrementing is irrelevant.
        source.incrementCompletedUnitCount(by: 0)
        source.incrementCompletedUnitCount(by: 50)
        // Should complete after a single progress update.
        var numUpdates = 0
        for await progress in stream {
            numUpdates += 1
            switch numUpdates {
            case 1:
                XCTAssertEqual(progress.percentComplete, 1)
                XCTAssertEqual(progress.totalUnitCount, 0)
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssert(progress.isFinished)
            default:
                XCTFail("Unexpected update")
            }
        }
    }

    func testZeroUnitCount_nestedSource() async {
        let (sink, stream) = OWSProgress.createSink()
        let child = await sink.addChild(withLabel: "child", unitCount: 100)
        let source = await child.addSource(withLabel: "source", unitCount: 0)
        // Incrementing is irrelevant.
        source.incrementCompletedUnitCount(by: 0)
        source.incrementCompletedUnitCount(by: 100)
        // Should complete after 2 progress updates.
        var numUpdates = 0
        for await progress in stream {
            numUpdates += 1
            switch numUpdates {
            case 1:
                XCTAssertEqual(progress.percentComplete, 0)
                XCTAssertEqual(progress.totalUnitCount, 100)
                XCTAssertEqual(progress.completedUnitCount, 0)
                XCTAssertFalse(progress.isFinished)
                XCTAssertEqual(numUpdates, 1)
            case 2:
                XCTAssertEqual(progress.percentComplete, 1)
                XCTAssertEqual(progress.totalUnitCount, 100)
                XCTAssertEqual(progress.completedUnitCount, 100)
                XCTAssert(progress.isFinished)
            default:
                XCTFail("Unexpected update")
            }
        }
    }

    func testZeroUnitCount_manyChildrenOnRoot() async {
        let (sink, stream) = OWSProgress.createSink()
        let source1 = await sink.addSource(withLabel: "1", unitCount: 100)
        _ = await sink.addSource(withLabel: "2", unitCount: 0)
        // Should get 2 progress updates for the setup.
        var numUpdates = 0
        loop: for await progress in stream {
            numUpdates += 1
            XCTAssertEqual(progress.percentComplete, 0)
            XCTAssertEqual(progress.completedUnitCount, 0)
            XCTAssertEqual(progress.totalUnitCount, 100)
            XCTAssertFalse(progress.isFinished)
            switch numUpdates {
            case 1:
                break
            case 2:
                break loop
            default:
                XCTFail("Unexpected update")
            }
        }

        // Complete the only source with nonzero units, which
        // should complete the whole progress.
        source1.incrementCompletedUnitCount(by: 100)
        for await progress in stream {
            numUpdates += 1
            switch numUpdates {
            case 3:
                XCTAssertEqual(progress.percentComplete, 1)
                XCTAssertEqual(progress.completedUnitCount, 100)
                XCTAssertEqual(progress.totalUnitCount, 100)
                XCTAssert(progress.isFinished)
            default:
                XCTFail("Unexpected update")
            }
        }
    }

    func testZeroUnitCount_manyChildrenOnChild() async {
        let (sink, stream) = OWSProgress.createSink()
        let child = await sink.addChild(withLabel: "A", unitCount: 100)
        let source1 = await child.addSource(withLabel: "1", unitCount: 100)
        _ = await child.addSource(withLabel: "2", unitCount: 0)
        // Should get 3 progress updates for the setup.
        var numUpdates = 0
        loop: for await progress in stream {
            numUpdates += 1
            XCTAssertEqual(progress.percentComplete, 0)
            XCTAssertEqual(progress.completedUnitCount, 0)
            XCTAssertEqual(progress.totalUnitCount, 100)
            XCTAssertFalse(progress.isFinished)
            switch numUpdates {
            case 1, 2:
                break
            case 3:
                break loop
            default:
                XCTFail("Unexpected update")
            }
        }

        // Complete the only source with nonzero units, which
        // should complete the whole progress.
        source1.incrementCompletedUnitCount(by: 100)
        for await progress in stream {
            numUpdates += 1
            switch numUpdates {
            case 4:
                XCTAssertEqual(progress.percentComplete, 1)
                XCTAssertEqual(progress.completedUnitCount, 100)
                XCTAssertEqual(progress.totalUnitCount, 100)
                XCTAssert(progress.isFinished)
            default:
                XCTFail("Unexpected update")
            }
        }
    }

    // MARK: - Sequential progress

    func testSequentialProgress() async {
        enum Step: String, OWSSequentialProgressStep {
            case first
            case second
            case third

            var progressUnitCount: UInt64 {
                switch self {
                case .first: 1
                case .second: 2
                case .third: 1
                }
            }
        }

        let (root, stream) = await OWSSequentialProgress<Step>.createSink()
        let source1a = await root.child(for: .first).addSource(withLabel: "a", unitCount: 1)
        let source2b = await root.child(for: .second).addSource(withLabel: "b", unitCount: 1)
        let source2c = await root.child(for: .second).addSource(withLabel: "c", unitCount: 1)
        let source3d = await root.child(for: .third).addSource(withLabel: "d", unitCount: 1)

        // Skip over the updates from the first 6 setup steps.
        var numUpdates = 0
        for await _ in stream {
            numUpdates += 1
            if numUpdates == 6 {
                break
            }
        }

        var outputs = [OWSSequentialProgress<Step>]()

        func awaitOneUpdate() async {
            for await progress in stream {
                outputs.append(progress)
                break
            }
        }
        await awaitOneUpdate()
        source1a.incrementCompletedUnitCount(by: 1)
        await awaitOneUpdate()
        source2b.incrementCompletedUnitCount(by: 1)
        await awaitOneUpdate()
        source2c.incrementCompletedUnitCount(by: 1)
        await awaitOneUpdate()
        source3d.incrementCompletedUnitCount(by: 1)
        await awaitOneUpdate()
        let allowedOutputs: [(UInt64, Step)] = [
            (0, .first),
            (1, .second),
            (2, .second),
            (3, .third),
            (4, .third),
        ]
        XCTAssertEqual(allowedOutputs.count, outputs.count)
        for i in 0..<allowedOutputs.count {
            XCTAssertEqual(allowedOutputs[i].0, outputs[i].completedUnitCount)
            XCTAssertEqual(allowedOutputs[i].1, outputs[i].currentStep)
        }
        XCTAssert(outputs.last?.isFinished == true)
    }
}
