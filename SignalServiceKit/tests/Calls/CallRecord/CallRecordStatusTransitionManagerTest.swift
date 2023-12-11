//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

private typealias IndividualCallStatus = CallRecord.CallStatus.IndividualCallStatus
private typealias GroupCallStatus = CallRecord.CallStatus.GroupCallStatus

private typealias StatusTransitionType = Hashable & CaseIterable
private typealias IndividualStatusTransition = StatusTransition<IndividualCallStatus, IndividualCallStatus>
private typealias GroupStatusTransition = StatusTransition<GroupCallStatus, GroupCallStatus>

final class IndividualCallRecordStatusTransitionManagerTest: XCTestCase {
    private var statusTransitionManager: IndividualCallRecordStatusTransitionManager!

    override func setUp() {
        statusTransitionManager = IndividualCallRecordStatusTransitionManager()
    }

    func testTransitions() {
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
                    fromIndividualCallStatus: transition.from,
                    toIndividualCallStatus: transition.to
                ),
                allowedTransitions.contains(transition)
            )
        }
    }
}

final class GroupCallRecordStatusTransitionManagerTest: XCTestCase {
    private var statusTransitionManager: GroupCallRecordStatusTransitionManager!

    override func setUp() {
        statusTransitionManager = GroupCallRecordStatusTransitionManager()
    }

    func testGroupTransitions() {
        let allowedTransitions: Set<GroupStatusTransition> = [
            [.generic, .joined],
            [.generic, .ringing],
            [.generic, .ringingMissed],
            [.generic, .ringingDeclined],
            [.generic, .ringingAccepted],
            [.joined, .ringingAccepted],
            [.ringing, .joined], // This indicates something is wrong, but if something is we don't want this manager to give us trouble.
            [.ringing, .ringingMissed],
            [.ringing, .ringingDeclined],
            [.ringing, .ringingAccepted],
            [.ringingDeclined, .ringingAccepted],
            [.ringingMissed, .ringingDeclined],
            [.ringingMissed, .ringingAccepted],
        ]

        for transition in GroupStatusTransition.all {
            let actual = statusTransitionManager.isStatusTransitionAllowed(
                fromGroupCallStatus: transition.from,
                toGroupCallStatus: transition.to
            )

            let expected = allowedTransitions.contains(transition)

            XCTAssertEqual(actual, expected, "Transition \(transition) had unexpected result."
            )
        }
    }
}

// MARK: -

private struct StatusTransition<FromType: StatusTransitionType, ToType: StatusTransitionType>: Hashable {
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

extension StatusTransition: ExpressibleByArrayLiteral where FromType == ToType {
    typealias ArrayLiteralElement = FromType

    init(arrayLiteral elements: ToType...) {
        guard elements.count == 2 else {
            owsFail("Incorrect number of elements!")
        }

        self.init(from: elements[0], to: elements[1])
    }
}
