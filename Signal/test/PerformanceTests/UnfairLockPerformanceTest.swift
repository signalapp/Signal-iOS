//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import SignalServiceKit

class UnfairLockPerformanceTest: PerformanceBaseTest {

    private let iterationCount: UInt64 = DebugFlags.fastPerfTests ? 100 : 1000 * 1000

    // A simple "happy path" test with no contention or load.
    func testUnfairLock() {
        let unfairLock = UnfairLock()
        var protectedValue: UInt64 = 0

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: true) {
            for _ in 0..<iterationCount {
                unfairLock.withLock {
                    protectedValue += 1
                }
            }
        }

        if protectedValue == iterationCount {
            Logger.verbose("Values match.")
        } else {
            owsFailDebug("Value do not match.")
        }
    }

    // A simple "happy path" test with no contention or load.
    func testSerialQueue() {
        let fairQueue = DispatchQueue(label: "UnfairLockPerformanceTest")
        var protectedValue: UInt64 = 0

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: true) {
            for _ in 0..<iterationCount {
                fairQueue.sync {
                    protectedValue += 1
                }
            }
        }

        if protectedValue == iterationCount {
            Logger.verbose("Values match.")
        } else {
            owsFailDebug("Value do not match.")
        }
    }
}
