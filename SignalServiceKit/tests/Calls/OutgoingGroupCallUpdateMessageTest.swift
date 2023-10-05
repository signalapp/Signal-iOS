//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class OutgoingGroupCallUpdateMessageSerializationTest: SSKBaseTestSwift {
    /// Confirms that an ``OutgoingGroupCallUpdateMessage`` (de)serializes.
    func testGroupCallUpdateMessageRoundTrip() throws {
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

        let updateMessage = write { tx in
            return OutgoingGroupCallUpdateMessage(
                thread: GroupThreadFactory().create(transaction: tx),
                eraId: "beep boop",
                tx: tx
            )
        }

        let archivedData = try NSKeyedArchiver.archivedData(
            withRootObject: updateMessage,
            requiringSecureCoding: false
        )

        guard let deserializedMessage = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OutgoingGroupCallUpdateMessage.self,
            from: archivedData,
            requiringSecureCoding: false
        ) else {
            XCTFail("Failed to deserialize!")
            return
        }

        XCTAssertEqual(updateMessage, deserializedMessage)
        XCTAssertEqual(updateMessage.eraId, deserializedMessage.eraId)
    }

    /// Tests that an instance of this class that was serialized prior to the
    /// class' conversion to Swift still deserializes.
    ///
    /// This test contains a hardcoded representation of a serialized instance
    /// of this class from when it was ObjC. If this test fails, then data
    /// serialized on an old device may fail to deserialize.
    ///
    /// I believe the only place this could be serialized is in
    /// ``MessageSenderJobRecord``, which handles deserialization issues
    /// gracefully, but this test remains in case I'm wrong.
    func testObjcSerializedInstanceUnarchives() throws {
        let hardcodedObjcInstanceData: Data = try! .data(fromBase64Url: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBkLDEdISUpLTE1RV2Bmam1xd3qBgoeMkJGSVSRudWxs3xAdDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKystListMTIrLSs2LTg5LSsrLSs_LSpCKy0rRl8QE3JlY2VpdmVkQXRUaW1lc3RhbXBfEBJpc1ZpZXdPbmNlQ29tcGxldGVfEBxzdG9yZWRTaG91bGRTdGFydEV4cGlyZVRpbWVyXxAPZXhwaXJlU3RhcnRlZEF0ViRjbGFzc18QEWlzVmlld09uY2VNZXNzYWdlXxAPTVRMTW9kZWxWZXJzaW9uXxAWcmVjaXBpZW50QWRkcmVzc1N0YXRlc151bmlxdWVUaHJlYWRJZF8QFWhhc0xlZ2FjeU1lc3NhZ2VTdGF0ZVZzb3J0SWRfEBJpc0Zyb21MaW5rZWREZXZpY2VVZXJhSWRfEBJsZWdhY3lNZXNzYWdlU3RhdGVfEBxvdXRnb2luZ01lc3NhZ2VTY2hlbWFWZXJzaW9uXxAQZ3JvdXBNZXRhTWVzc2FnZV8QEGV4cGlyZXNJblNlY29uZHNfEBJsZWdhY3lXYXNEZWxpdmVyZWReaXNWb2ljZU1lc3NhZ2VZZXhwaXJlc0F0XxARaXNHcm91cFN0b3J5UmVwbHldc2NoZW1hVmVyc2lvblllZGl0U3RhdGVZdGltZXN0YW1wWHVuaXF1ZUlkXxASd2FzUmVtb3RlbHlEZWxldGVkXxASc3RvcmVkTWVzc2FnZVN0YXRlXxATaGFzU3luY2VkVHJhbnNjcmlwdF1hdHRhY2htZW50SWRzgAaAA4ADgAKAGIADgAKACoAFgAOAAoADgASAAoASgBaAAoADgAOAAoADgBeAAoAGgAeAA4ACgAOACBAACFlib2JhIGZldHRfEBlna1hJOWFmWTkrVzRCUEZIU0JEWjhXQT09EwAAAYn12quGXxAkQzVBNjNERTUtOEZCOC00OUEzLTk1MDgtOTRBQzcyRERGMEI50k4RT1BaTlMub2JqZWN0c6CACdJSU1RVWiRjbGFzc25hbWVYJGNsYXNzZXNXTlNBcnJheaJUVlhOU09iamVjdNNYThFZXF9XTlMua2V5c6JaW4ALgA-iXV6AEYAUgBXTEWFiY2RlW2JhY2tpbmdVdWlkXxASYmFja2luZ1Bob25lTnVtYmVygA6ADIAA0mcRaGlcTlMudXVpZGJ5dGVzTxAQeOsX1A2qSdW57kKHFcmOvoAN0lJTa2xWTlNVVUlEomtW0lJTbm9fECVTaWduYWxTZXJ2aWNlS2l0LlNpZ25hbFNlcnZpY2VBZGRyZXNzonBWXxAlU2lnbmFsU2VydmljZUtpdC5TaWduYWxTZXJ2aWNlQWRkcmVzc9MRcnNjdWVbYmFja2luZ1V1aWRfEBJiYWNraW5nUGhvbmVOdW1iZXKADoAQgADSZxF4aU8QEMZolRAJIUBZgxS6bb5tEBWADdQRexN8fTgtK1VzdGF0ZVt3YXNTZW50QnlVRIATgBKAAoADEAHSUlODhF8QH1RTT3V0Z29pbmdNZXNzYWdlUmVjaXBpZW50U3RhdGWjhYZWXxAfVFNPdXRnb2luZ01lc3NhZ2VSZWNpcGllbnRTdGF0ZVhNVExNb2RlbNQRexN8fTgtK4ATgBKAAoAD0lJTjY5cTlNEaWN0aW9uYXJ5oo9WXE5TRGljdGlvbmFyeRADEATSUlOTlF8QG09XU091dGdvaW5nR3JvdXBDYWxsTWVzc2FnZaiVlpeYmZqGVl8QG09XU091dGdvaW5nR3JvdXBDYWxsTWVzc2FnZV8QEVRTT3V0Z29pbmdNZXNzYWdlWVRTTWVzc2FnZV1UU0ludGVyYWN0aW9uWUJhc2VNb2RlbF8QE1RTWWFwRGF0YWJhc2VPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAG8AdQCyAMgA3QD8AQ4BFQEpATsBVAFjAXsBggGXAZ0BsgHRAeQB9wIMAhsCJQI5AkcCUQJbAmQCeQKOAqQCsgK0ArYCuAK6ArwCvgLAAsICxALGAsgCygLMAs4C0ALSAtQC1gLYAtoC3ALeAuAC4gLkAuYC6ALqAuwC7gLvAvkDFQMeA0UDSgNVA1YDWANdA2gDcQN5A3wDhQOMA5QDlwOZA5sDngOgA6IDpAOrA7cDzAPOA9AD0gPXA-QD9wP5A_4EBQQIBA0ENQQ4BGAEZwRzBIgEigSMBI4EkwSmBKgEsQS3BMMExQTHBMkEywTNBNIE9AT4BRoFIwUsBS4FMAUyBTQFOQVGBUkFVgVYBVoFXwV9BYYFpAW4BcIF0AXaAAAAAAAAAgEAAAAAAAAAmwAAAAAAAAAAAAAAAAAABfA")

        guard let updateMessage = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: OutgoingGroupCallUpdateMessage.self,
            from: hardcodedObjcInstanceData,
            requiringSecureCoding: false
        ) else {
            XCTFail("Failed to unarchive!")
            return
        }

        XCTAssertEqual(updateMessage.eraId, "boba fett")
    }
}
