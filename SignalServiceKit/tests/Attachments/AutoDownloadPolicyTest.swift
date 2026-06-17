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
        case (.never, .never): true
        case (.preference(let lhs), .preference(let rhs)): lhs == rhs
        case (.always, .always): true
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
            var plaintextSize: UInt64
            var expectedPolicy: AutoDownloadPolicy
        }

        @Test(arguments: [
            TestCase(context: .body, mimeType: "image/jpeg", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .preference(mediaType: .photo)),
            TestCase(context: .body, mimeType: "image/jpeg", renderingFlag: .default, plaintextSize: 199_000_000, expectedPolicy: .never),
            TestCase(context: .body, mimeType: "video/mp4", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .preference(mediaType: .video)),
            TestCase(context: .body, mimeType: "video/mp4", renderingFlag: .default, plaintextSize: 500_000_000, expectedPolicy: .never),
            TestCase(context: .body, mimeType: "audio/aac", renderingFlag: .voiceMessage, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .body, mimeType: "audio/aac", renderingFlag: .voiceMessage, plaintextSize: 100_001, expectedPolicy: .preference(mediaType: .audio)),
            TestCase(context: .body, mimeType: "audio/aac", renderingFlag: .voiceMessage, plaintextSize: 200_000_001, expectedPolicy: .never),
            TestCase(context: .body, mimeType: "audio/aac", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .preference(mediaType: .audio)),
            TestCase(context: .body, mimeType: "text/plain", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .preference(mediaType: .document)),
            TestCase(context: .body, mimeType: "text/plain", renderingFlag: .default, plaintextSize: 200_000_000, expectedPolicy: .never),
            TestCase(context: .text, mimeType: "text/x-signal-plain", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .text, mimeType: "text/plain", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .text, mimeType: "image/jpeg", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .sticker, mimeType: "image/webp", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .sticker, mimeType: "image/webp", renderingFlag: .default, plaintextSize: 101_000, expectedPolicy: .preference(mediaType: .photo)),
            TestCase(context: .sticker, mimeType: "video/mp4", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .link, mimeType: "image/png", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .reply, mimeType: "image/jpeg", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
            TestCase(context: .wallpaper, mimeType: "image/png", renderingFlag: .default, plaintextSize: 50_000, expectedPolicy: .always),
        ])
        func testForMimeType(testCase: TestCase) {
            let actualPolicy = AutoDownloadPolicy.build(
                context: testCase.context,
                mimeType: testCase.mimeType,
                renderingFlag: testCase.renderingFlag,
                plaintextSize: testCase.plaintextSize,
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
