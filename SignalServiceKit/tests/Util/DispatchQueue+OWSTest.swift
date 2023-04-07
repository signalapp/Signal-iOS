//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class DispatchQueueOWSTests: XCTestCase {

    func testQoSFlooring() {
        // Setup: Construct a map, (QoSClass) -> (UInt32 that should floor to its key)
        let expectedQoSForRawValues: [DispatchQoS.QoSClass: [UInt32]] = [
            .background: [
                QOS_CLASS_BACKGROUND.rawValue,
                QOS_CLASS_BACKGROUND.rawValue + 1,
                QOS_CLASS_UTILITY.rawValue - 1
            ],
            .utility: [
                QOS_CLASS_UTILITY.rawValue,
                QOS_CLASS_UTILITY.rawValue + 1,
                QOS_CLASS_USER_INITIATED.rawValue - 1
            ],
            .userInitiated: [
                QOS_CLASS_USER_INITIATED.rawValue,
                QOS_CLASS_USER_INITIATED.rawValue + 1,
                QOS_CLASS_USER_INTERACTIVE.rawValue - 1
            ],
            .userInteractive: [QOS_CLASS_USER_INTERACTIVE.rawValue]
        ]

        // Test: Map the raw UInt32s to a QoSClass by flooring
        let resultMap = expectedQoSForRawValues.mapValues { (rawValueArray) in
            rawValueArray
                .map { qos_class_t(rawValue: $0)}
                .map { DispatchQoS.QoSClass(flooring: $0) }
        }

        // Verify: Each mapped QoS class in the value array should match its key
        resultMap.forEach { (key, valueArray) in
            valueArray.forEach { XCTAssertEqual(key, $0) }
        }
    }

    func testSharedQueues() {
        // Setup + Test: Access queues in all sorts of different ways
        let sharedQueuesAtQoS: [DispatchQoS.QoSClass: [DispatchQueue]] = [
            .background: [
                DispatchQueue.sharedBackground,
                DispatchQueue.sharedQueue(at: .background)
            ],
            .utility: [
                DispatchQueue.sharedUtility,
                DispatchQueue.sharedQueue(at: .utility)
            ],
            .userInitiated: [
                DispatchQueue.sharedUserInitiated,
                DispatchQueue.sharedQueue(at: .userInitiated)
            ],
            .userInteractive: [
                DispatchQueue.sharedUserInteractive,
                DispatchQueue.sharedQueue(at: .userInteractive)
            ]
        ]

        // Verify: All shared queues should refer to the same serial queue at the correct QoS
        sharedQueuesAtQoS.forEach { (qos, queueArray) in
            let firstQueue = queueArray[0]
            queueArray.forEach { queue in
                XCTAssertEqual(queue.qos.qosClass, qos)
                XCTAssertEqual(queue, firstQueue)
            }
        }
    }
}
