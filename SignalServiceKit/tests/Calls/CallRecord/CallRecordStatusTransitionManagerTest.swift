//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class CallRecordStatusTransitionManagerTest: XCTestCase {
    typealias CallStatus = CallRecord.CallStatus
    typealias IndividualCallStatus = CallStatus.IndividualCallStatus
    typealias GroupCallStatus = CallStatus.GroupCallStatus

    private var statusTransitionManager: CallRecordStatusTransitionManagerImpl!

    override func setUp() {
        statusTransitionManager = CallRecordStatusTransitionManagerImpl()
    }

    func testTransitionBetweenCasesFails() {
        let individualToGroupCases = StatusTransition<IndividualCallStatus, GroupCallStatus>.all
        let groupToIndividualCases = StatusTransition<GroupCallStatus, IndividualCallStatus>.all

        for i2g in individualToGroupCases {
            XCTAssertFalse(statusTransitionManager.isStatusTransitionAllowed(
                from: .individual(i2g.from),
                to: .group(i2g.to)
            ))
        }

        for g2i in groupToIndividualCases {
            XCTAssertFalse(statusTransitionManager.isStatusTransitionAllowed(
                from: .group(g2i.from),
                to: .individual(g2i.to)
            ))
        }
    }

    func testIndividualTransitions() {
        let allowedTransitions: Set<IndividualStatusTransition> = [
            [.pending, .incomingMissed],
            [.pending, .notAccepted],
            [.pending, .accepted],
            [.notAccepted, .accepted],
            [.incomingMissed, .notAccepted],
            [.incomingMissed, .accepted],
        ]

        for transition in IndividualStatusTransition.all {
            XCTAssertEqual(
                statusTransitionManager.isStatusTransitionAllowed(
                    from: .individual(transition.from),
                    to: .individual(transition.to)
                ),
                allowedTransitions.contains(transition)
            )
        }
    }

    func testGroupTransitions() {
        let allowedTransitions: Set<GroupStatusTransition> = [
            [.generic, .joined],
            [.generic, .incomingRingingMissed],
            [.generic, .ringingNotAccepted],
            [.generic, .ringingAccepted],
            [.joined, .ringingAccepted],
            [.ringingNotAccepted, .ringingAccepted],
            [.incomingRingingMissed, .ringingNotAccepted],
            [.incomingRingingMissed, .ringingAccepted],
        ]

        for transition in GroupStatusTransition.all {
            XCTAssertEqual(
                statusTransitionManager.isStatusTransitionAllowed(
                    from: .group(transition.from),
                    to: .group(transition.to)
                ),
                allowedTransitions.contains(transition)
            )
        }
    }
}

// MARK: - Status transitions

private extension CallRecordStatusTransitionManagerTest {
    typealias StatusTransitionType = Hashable & CaseIterable
    typealias IndividualStatusTransition = StatusTransition<IndividualCallStatus, IndividualCallStatus>
    typealias GroupStatusTransition = StatusTransition<GroupCallStatus, GroupCallStatus>

    struct StatusTransition<FromType: StatusTransitionType, ToType: StatusTransitionType>: Hashable {
        let from: FromType
        let to: ToType

        static var all: Set<StatusTransition<FromType, ToType>> {
            var cases: Set<StatusTransition<FromType, ToType>> = []

            for fromStatus in FromType.allCases {
                for toStatus in ToType.allCases {
                    cases.insert(StatusTransition(from: fromStatus, to: toStatus))
                }
            }

            return cases
        }
    }
}

extension CallRecordStatusTransitionManagerTest.StatusTransition: ExpressibleByArrayLiteral where FromType == ToType {
    typealias ArrayLiteralElement = FromType

    init(arrayLiteral elements: ToType...) {
        guard elements.count == 2 else {
            owsFail("Incorrect number of elements!")
        }

        self.init(from: elements[0], to: elements[1])
    }
}
