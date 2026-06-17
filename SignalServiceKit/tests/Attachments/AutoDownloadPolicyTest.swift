//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

extension AutoDownloadPolicy: @retroactive Equatable {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.always, .always): true
        case (.preference(let lhs), .preference(let rhs)): lhs == rhs
        default: false
        }
    }
}

enum AutoDownloadPolicyTest {
    struct ForMimeType {
        struct TestCase {
            var context: AutoDownloadPolicy.AttachmentContext
            var mimeType: String
            var renderingFlag: AttachmentReference.RenderingFlag
            var expectedPolicy: AutoDownloadPolicy
        }

        @Test(arguments: [
            TestCase(context: .body, mimeType: "image/jpeg", renderingFlag: .default, expectedPolicy: .preference(mediaType: .photo)),
            TestCase(context: .body, mimeType: "video/mp4", renderingFlag: .default, expectedPolicy: .preference(mediaType: .video)),
            TestCase(context: .body, mimeType: "audio/aac", renderingFlag: .voiceMessage, expectedPolicy: .always),
            TestCase(context: .body, mimeType: "audio/aac", renderingFlag: .default, expectedPolicy: .preference(mediaType: .audio)),
            TestCase(context: .body, mimeType: "text/plain", renderingFlag: .default, expectedPolicy: .preference(mediaType: .document)),
            TestCase(context: .text, mimeType: "text/x-signal-plain", renderingFlag: .default, expectedPolicy: .always),
            TestCase(context: .text, mimeType: "text/plain", renderingFlag: .default, expectedPolicy: .always),
            TestCase(context: .text, mimeType: "image/jpeg", renderingFlag: .default, expectedPolicy: .always),
            TestCase(context: .sticker, mimeType: "image/webp", renderingFlag: .default, expectedPolicy: .preference(mediaType: .photo)),
            TestCase(context: .sticker, mimeType: "video/mp4", renderingFlag: .default, expectedPolicy: .preference(mediaType: .photo)),
            TestCase(context: .link, mimeType: "image/png", renderingFlag: .default, expectedPolicy: .always),
            TestCase(context: .reply, mimeType: "image/jpeg", renderingFlag: .default, expectedPolicy: .always),
            TestCase(context: .wallpaper, mimeType: "image/png", renderingFlag: .default, expectedPolicy: .always),
        ])
        func testForMimeType(testCase: TestCase) {
            let actualPolicy = AutoDownloadPolicy.build(
                context: testCase.context,
                mimeType: testCase.mimeType,
                renderingFlag: testCase.renderingFlag,
            )
            #expect(actualPolicy == testCase.expectedPolicy)
        }
    }

    struct CanAutoDownload {
        let db = InMemoryDB()
        let store = MediaBandwidthPreferenceStore()

        struct TestCase {
            var preference: MediaBandwidthPreferences.Preference
            var isReachableViaWiFi: Bool
            var result: Bool
        }

        @Test(arguments: [
            TestCase(preference: .never, isReachableViaWiFi: false, result: false),
            TestCase(preference: .never, isReachableViaWiFi: true, result: false),
            TestCase(preference: .wifiOnly, isReachableViaWiFi: false, result: false),
            TestCase(preference: .wifiOnly, isReachableViaWiFi: true, result: true),
            TestCase(preference: .wifiAndCellular, isReachableViaWiFi: false, result: true),
            TestCase(preference: .wifiAndCellular, isReachableViaWiFi: false, result: true),
        ])
        func testCanAutoDownload(testCase: TestCase) {
            db.write { tx in
                store.set(testCase.preference, for: .photo, tx: tx)
            }
            let actualResult = db.read { tx in
                return AutoDownloadPolicy.canAutoDownload(
                    mediaType: .photo,
                    preferenceStore: store,
                    isReachableViaWiFi: { testCase.isReachableViaWiFi },
                    tx: tx,
                )
            }
            #expect(actualResult == testCase.result)
        }
    }
}
