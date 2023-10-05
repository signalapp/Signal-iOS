//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class OutgoingCallEventSyncMessageSerializationTest: SSKBaseTestSwift {
    /// ``OutgoingCallEventSyncMessage`` used to be defined in ObjC. This test
    /// contains a hardcoded base64url-encoded representation of an instance of
    /// that class that was archived:
    /// ```swift
    /// NSKeyedArchiver.archivedData(
    ///     withRootObject: callEventSyncMessage,
    ///     requiringSecureCoding: false
    /// )
    /// ```
    /// before the class was migrated to Swift, using hardcoded parameters.
    ///
    /// If this test fails, then it's possible that a persisted instance of the
    /// legacy model will fail to deserialize.
    ///
    /// - Note
    /// At the time of writing, I believe the only place this could be persisted
    /// is on a ``MessageSenderJobRecord``, as an "invisible message", whose
    /// deserialization errors are handled gracefully.
    ///
    /// This test remains just in case I'm wrong.
    func testObjcSerializedInstanceDecodes() throws {
        let archivedObjCCallEventSyncMessage: Data = try! .data(fromBase64Url: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBkLDEdISUpLTFBWXWNnam51dnt_jI2Oj5OUVSRudWxs3xAdDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKystListMTIzKy0rLS0tOisrLSs_LSpCKy0rRl8QE3JlY2VpdmVkQXRUaW1lc3RhbXBfEBJpc1ZpZXdPbmNlQ29tcGxldGVfEBxzdG9yZWRTaG91bGRTdGFydEV4cGlyZVRpbWVyXxAPZXhwaXJlU3RhcnRlZEF0ViRjbGFzc18QEWlzVmlld09uY2VNZXNzYWdlXxAPTVRMTW9kZWxWZXJzaW9uXxAWcmVjaXBpZW50QWRkcmVzc1N0YXRlc18QHG91dGdvaW5nTWVzc2FnZVNjaGVtYVZlcnNpb25edW5pcXVlVGhyZWFkSWRfEBVoYXNMZWdhY3lNZXNzYWdlU3RhdGVWc29ydElkXxASaXNGcm9tTGlua2VkRGV2aWNlXxASbGVnYWN5TWVzc2FnZVN0YXRlXxAQZ3JvdXBNZXRhTWVzc2FnZV8QEGV4cGlyZXNJblNlY29uZHNVZXZlbnRfEBJsZWdhY3lXYXNEZWxpdmVyZWReaXNWb2ljZU1lc3NhZ2VZZXhwaXJlc0F0XxARaXNHcm91cFN0b3J5UmVwbHldc2NoZW1hVmVyc2lvblllZGl0U3RhdGVZdGltZXN0YW1wWHVuaXF1ZUlkXxASd2FzUmVtb3RlbHlEZWxldGVkXxASc3RvcmVkTWVzc2FnZVN0YXRlXxATaGFzU3luY2VkVHJhbnNjcmlwdF1hdHRhY2htZW50SWRzgAWAA4ADgAKAGIADgAKACYAPgASAA4ACgAOAAoACgAKAEoADgAOAAoADgBeAAoAFgAaAA4ACgAOABxAACF8QJEE3QUY2MDE4LTQ1QjgtNDE1OS1CN0ZBLTJFQzU4NDcxOTQxQhMAAAGJ5pgwTl8QJDQyNkE3NjA5LTU2NzUtNDc4Ni1BOUFFLUVEM0Q5NEQ4Mzc3MdJNEU5PWk5TLm9iamVjdHOggAjSUVJTVFokY2xhc3NuYW1lWCRjbGFzc2VzV05TQXJyYXmiU1VYTlNPYmplY3TTV00RWFpcV05TLmtleXOhWYAKoVuADoAR0xFeX2BhYltiYWNraW5nVXVpZF8QEmJhY2tpbmdQaG9uZU51bWJlcoANgAuAANJkEWVmXE5TLnV1aWRieXRlc08QEPUX-TuWCUg-n4inEYLbHKuADNJRUmhpVk5TVVVJRKJoVdJRUmtsXxAlU2lnbmFsU2VydmljZUtpdC5TaWduYWxTZXJ2aWNlQWRkcmVzc6JtVV8QJVNpZ25hbFNlcnZpY2VLaXQuU2lnbmFsU2VydmljZUFkZHJlc3PUEW8TcHEyLStVc3RhdGVbd2FzU2VudEJ5VUSAEIAPgAKAAxAB0lFSd3hfEB9UU091dGdvaW5nTWVzc2FnZVJlY2lwaWVudFN0YXRlo3l6VV8QH1RTT3V0Z29pbmdNZXNzYWdlUmVjaXBpZW50U3RhdGVYTVRMTW9kZWzSUVJ8fVxOU0RpY3Rpb25hcnmiflVcTlNEaWN0aW9uYXJ52IARgRMdgiSDhIWGLS0tii1WY2FsbElkWHBlZXJVdWlkVHR5cGVZZGlyZWN0aW9ugBOAFoAVgAKAAoACgBSAAhEwORIAAYHNTxAQ-aLPZIRWRHittTOA3trmItJRUpCRXxART3V0Z29pbmdDYWxsRXZlbnSjknpVXxART3V0Z29pbmdDYWxsRXZlbnQQBNJRUpWWXxAcT3V0Z29pbmdDYWxsRXZlbnRTeW5jTWVzc2FnZamXmJmam5ydelVfEBxPdXRnb2luZ0NhbGxFdmVudFN5bmNNZXNzYWdlXxAWT1dTT3V0Z29pbmdTeW5jTWVzc2FnZV8QEVRTT3V0Z29pbmdNZXNzYWdlWVRTTWVzc2FnZV1UU0ludGVyYWN0aW9uWUJhc2VNb2RlbF8QE1RTWWFwRGF0YWJhc2VPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAG8AdQCyAMgA3QD8AQ4BFQEpATsBVAFzAYIBmgGhAbYBywHeAfEB9wIMAhsCJQI5AkcCUQJbAmQCeQKOAqQCsgK0ArYCuAK6ArwCvgLAAsICxALGAsgCygLMAs4C0ALSAtQC1gLYAtoC3ALeAuAC4gLkAuYC6ALqAuwC7gLvAxYDHwNGA0sDVgNXA1kDXgNpA3IDegN9A4YDjQOVA5cDmQObA50DnwOmA7IDxwPJA8sDzQPSA98D8gP0A_kEAAQDBAgEMAQzBFsEZARqBHYEeAR6BHwEfgSABIUEpwSrBM0E1gTbBOgE6wT4BQkFEAUZBR4FKAUqBSwFLgUwBTIFNAU2BTgFOwVABVMFWAVsBXAFhAWGBYsFqgW0BdMF7AYABgoGGAYiAAAAAAAAAgEAAAAAAAAAngAAAAAAAAAAAAAAAAAABjg")

        guard let syncMessage = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OutgoingCallEventSyncMessage.self,
            from: archivedObjCCallEventSyncMessage,
            requiringSecureCoding: false
        ) else {
            XCTFail("Failed to decode sync message!")
            return
        }

        XCTAssertEqual(syncMessage.callEvent.callId, 12345)
        XCTAssertEqual(syncMessage.callEvent.callType, .audio)
        XCTAssertEqual(syncMessage.callEvent.eventDirection, .incoming)
        XCTAssertEqual(syncMessage.callEvent.eventType, .accepted)
        XCTAssertEqual(syncMessage.callEvent.timestamp, 98765)
        XCTAssertEqual(
            syncMessage.callEvent.conversationId,
            UUID(uuidString: "F9A2CF64-8456-4478-ADB5-3380DEDAE622")!.data
        )
    }

    /// This test simply confirms that an instance of
    /// ``OutgoingCallEventSyncMessage`` will continue to serialize/deserialize
    /// correctly. This should be trivial, but Mantle makes me nervous.
    func testCallEventRoundTrip() throws {
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

        let syncMessage: OutgoingCallEventSyncMessage = write { tx in
            return OutgoingCallEventSyncMessage(
                thread: ContactThreadFactory().create(transaction: tx),
                event: OutgoingCallEvent(
                    timestamp: 98765,
                    conversationId: UUID().data,
                    callId: 12345,
                    callType: .video,
                    eventDirection: .outgoing,
                    eventType: .notAccepted
                ),
                tx: tx
            )
        }

        let archivedData = try NSKeyedArchiver.archivedData(
            withRootObject: syncMessage,
            requiringSecureCoding: false
        )

        guard let deserializedSyncMessage = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OutgoingCallEventSyncMessage.self,
            from: archivedData,
            requiringSecureCoding: false
        ) else {
            XCTFail("Got nil when unarchiving!")
            return
        }

        XCTAssertEqual(
            syncMessage.callEvent.callId,
            deserializedSyncMessage.callEvent.callId
        )
        XCTAssertEqual(
            syncMessage.callEvent.callType,
            deserializedSyncMessage.callEvent.callType
        )
        XCTAssertEqual(
            syncMessage.callEvent.eventDirection,
            deserializedSyncMessage.callEvent.eventDirection
        )
        XCTAssertEqual(
            syncMessage.callEvent.eventType,
            deserializedSyncMessage.callEvent.eventType
        )
        XCTAssertEqual(
            syncMessage.callEvent.timestamp,
            deserializedSyncMessage.callEvent.timestamp
        )
        XCTAssertEqual(
            syncMessage.callEvent.conversationId,
            deserializedSyncMessage.callEvent.conversationId
        )
    }
}
