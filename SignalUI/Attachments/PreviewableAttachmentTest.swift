//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit
import XCTest

@testable import SignalUI

final class PreviewableAttachmentTest: XCTestCase {
    private let maxFileSize: UInt64 = 95 * 1024 * 1024

    private func presetNames(
        qualityLevel: ImageQualityLevel,
        durationSeconds: Double,
    ) -> [String] {
        return PreviewableAttachment.videoExportTiers(
            forQualityLevel: qualityLevel,
            videoDuration: CMTime(seconds: durationSeconds, preferredTimescale: 600),
            maxFileSize: maxFileSize,
        ).map(\.presetName)
    }

    func testReducedQualityOnlyOffers640x480() {
        XCTAssertEqual(
            presetNames(qualityLevel: .one, durationSeconds: 30),
            [AVAssetExportPreset640x480],
        )
    }

    func testStandardQualityStartsAt720p() {
        XCTAssertEqual(
            presetNames(qualityLevel: .two, durationSeconds: 30),
            [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480],
        )
    }

    func testHighQualityStartsAt1080p() {
        XCTAssertEqual(
            presetNames(qualityLevel: .three, durationSeconds: 30),
            [
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPreset960x540,
                AVAssetExportPreset640x480,
            ],
        )
    }

    func testLongVideosSkipTiersThatWouldExceedTheSizeLimit() {
        // A two minute video is estimated to exceed ~95MB at 1080p, so the
        // first export should be attempted at 720p instead.
        XCTAssertEqual(
            presetNames(qualityLevel: .three, durationSeconds: 120),
            [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480],
        )
    }

    func testLastResortTierIsNeverDropped() {
        // Even if the estimated output of the lowest-quality tier exceeds
        // the size limit, it must be retained so that very long videos can
        // still be sent (and validated after export).
        XCTAssertEqual(
            presetNames(qualityLevel: .three, durationSeconds: 60 * 60),
            [AVAssetExportPreset640x480],
        )
    }

    func testIndefiniteDurationOffersAllTiers() {
        let tiers = PreviewableAttachment.videoExportTiers(
            forQualityLevel: .three,
            videoDuration: .indefinite,
            maxFileSize: maxFileSize,
        ).map(\.presetName)
        XCTAssertEqual(tiers.first, AVAssetExportPreset1920x1080)
        XCTAssertEqual(tiers.count, 4)
    }
}
