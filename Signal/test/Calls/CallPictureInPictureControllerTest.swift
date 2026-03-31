//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
import AVFoundation
import XCTest

@testable import Signal

final class CallPictureInPictureControllerTest: XCTestCase {

    @MainActor
    func testPiPControllerInitialization() {
        let controller = CallPictureInPictureController()
        XCTAssertFalse(controller.isPictureInPictureActive)
    }

    @MainActor
    func testAttachAndDetachRemoteVideoTrack() {
        let controller = CallPictureInPictureController()
        controller.attachRemoteVideoTrack(nil)
        XCTAssertFalse(controller.isPictureInPictureActive)
        controller.attachRemoteVideoTrack(nil)
    }

    @MainActor
    func testTearDown() {
        let controller = CallPictureInPictureController()
        controller.tearDown()
        XCTAssertFalse(controller.isPictureInPictureActive)
    }

    @MainActor
    func testCallbacksAreSet() {
        let controller = CallPictureInPictureController()
        var restoreCalled = false
        var stopCalled = false
        controller.onRestoreUserInterface = { restoreCalled = true }
        controller.onPictureInPictureDidStop = { stopCalled = true }
        controller.onRestoreUserInterface?()
        controller.onPictureInPictureDidStop?()
        XCTAssertTrue(restoreCalled)
        XCTAssertTrue(stopCalled)
    }

    @MainActor
    func testMultipleTearDownsAreSafe() {
        let controller = CallPictureInPictureController()
        controller.tearDown()
        controller.tearDown()
    }

    /// AVSampleBufferDisplayLayer requires IOSurface-backed pixel buffers.
    /// Non-IOSurface buffers are silently dropped (grey output).
    func testIOSurfaceBackedBufferIsRequired() {
        // Non-IOSurface buffer
        var nonIOBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 320, 180,
                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            nil, &nonIOBuffer)
        XCTAssertNotNil(nonIOBuffer)
        XCTAssertNil(CVPixelBufferGetIOSurface(nonIOBuffer!))

        // IOSurface-backed buffer
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var ioBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 320, 180,
                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            attrs as CFDictionary, &ioBuffer)
        XCTAssertNotNil(ioBuffer)
        XCTAssertNotNil(CVPixelBufferGetIOSurface(ioBuffer!))
    }
}
