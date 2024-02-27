//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class OutogingCallLogEventSyncMessageTest: SSKBaseTestSwift {
    func testRoundTripSerialization() throws {
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .init(
                    aci: .init(fromUUID: UUID()),
                    pni: .init(fromUUID: UUID()),
                    e164: .init("+17735550199")!
                ),
                tx: tx.asV2Write
            )
        }

        for (idx, eventType) in OutgoingCallLogEventSyncMessage.CallLogEvent.EventType.allCases.enumerated() {
            let syncMessage: OutgoingCallLogEventSyncMessage = write { tx in
                return OutgoingCallLogEventSyncMessage(
                    callLogEvent: OutgoingCallLogEventSyncMessage.CallLogEvent(
                        eventType: eventType,
                        timestamp: UInt64(idx * 100)
                    ),
                    thread: ContactThreadFactory().create(transaction: tx),
                    tx: tx
                )
            }

            let archivedData = try NSKeyedArchiver.archivedData(
                withRootObject: syncMessage,
                requiringSecureCoding: false
            )

            guard let deserializedSyncMessage = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: OutgoingCallLogEventSyncMessage.self,
                from: archivedData,
                requiringSecureCoding: false
            ) else {
                XCTFail("Got nil when unarchiving!")
                return
            }

            XCTAssertEqual(
                syncMessage.callLogEvent.eventType,
                deserializedSyncMessage.callLogEvent.eventType
            )
            XCTAssertEqual(
                syncMessage.callLogEvent.timestamp,
                deserializedSyncMessage.callLogEvent.timestamp
            )
        }
    }
}
