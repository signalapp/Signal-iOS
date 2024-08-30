//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class OutgoingCallLogEventSyncMessageTest: XCTestCase {
    func testStableDecoding() throws {
        let archivedData = Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGlCwwTFBVVJG51bGzTDQ4PEBESViRjbGFzc1lldmVudFR5cGVZdGltZXN0YW1wgASAA4ACECoQANIWFxgZWiRjbGFzc25hbWVYJGNsYXNzZXNfEBRPdXRnb2luZ0NhbGxMb2dFdmVudKIaG18QFE91dGdvaW5nQ2FsbExvZ0V2ZW50WE5TT2JqZWN0CBEaJCkyN0lMUVNZX2Ztd4GDhYeJi5CbpLu+1QAAAAAAAAEBAAAAAAAAABwAAAAAAAAAAAAAAAAAAADe")!

        guard let deserializedSyncMessageEvent = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OutgoingCallLogEventSyncMessage.CallLogEvent.self,
            from: archivedData,
            requiringSecureCoding: false
        ) else {
            XCTFail("Got nil while archiving!")
            return
        }

        XCTAssertEqual(deserializedSyncMessageEvent.eventType, .cleared)
        XCTAssertEqual(deserializedSyncMessageEvent.timestamp, 42)
    }

    func testRoundTripSerialization() throws {
        for (idx, eventType) in OutgoingCallLogEventSyncMessage.CallLogEvent.EventType.allCases.enumerated() {
            let syncMessageEvents: [OutgoingCallLogEventSyncMessage.CallLogEvent] = [
                .init(
                    eventType: eventType,
                    callId: .maxRandom,
                    conversationId: Aci.randomForTesting().serviceIdBinary.asData,
                    timestamp: UInt64(idx * 100)
                ),
                .init(
                    eventType: eventType,
                    callId: nil,
                    conversationId: nil,
                    timestamp: UInt64(idx * 100)
                ),
            ]

            for syncMessageEvent in syncMessageEvents {
                let archivedData = try NSKeyedArchiver.archivedData(
                    withRootObject: syncMessageEvent,
                    requiringSecureCoding: false
                )

                guard let deserializedSyncMessageEvent = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: OutgoingCallLogEventSyncMessage.CallLogEvent.self,
                    from: archivedData,
                    requiringSecureCoding: false
                ) else {
                    XCTFail("Got nil when unarchiving!")
                    return
                }

                XCTAssertEqual(
                    syncMessageEvent.eventType,
                    deserializedSyncMessageEvent.eventType
                )
                XCTAssertEqual(
                    syncMessageEvent.callId,
                    deserializedSyncMessageEvent.callId
                )
                XCTAssertEqual(
                    syncMessageEvent.conversationId,
                    deserializedSyncMessageEvent.conversationId
                )
                XCTAssertEqual(
                    syncMessageEvent.timestamp,
                    deserializedSyncMessageEvent.timestamp
                )
            }
        }
    }
}
