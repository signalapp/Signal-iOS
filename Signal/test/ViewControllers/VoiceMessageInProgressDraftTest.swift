//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

class VoiceMessageInProgressDraftTest: SignalBaseTest {

    // MARK: - Test Helpers

    private class MockDeviceSleepManager: DeviceSleepManager {
        var addBlockCallCount = 0
        var removeBlockCallCount = 0

        func addBlock(blockObject: DeviceSleepBlockObject) {
            addBlockCallCount += 1
        }

        func removeBlock(blockObject: DeviceSleepBlockObject) {
            removeBlockCallCount += 1
        }
    }

    private class NoopAudioSession: AudioSession {
        override func startAudioActivity(_ audioActivity: AudioActivity) -> Bool { false }
        override func endAudioActivity(_ audioActivity: AudioActivity) {}
    }

    private func makeDraft(sleepManager: MockDeviceSleepManager = MockDeviceSleepManager()) -> VoiceMessageInProgressDraft {
        let thread = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+16505550100"))
        return VoiceMessageInProgressDraft(
            thread: thread,
            audioSession: NoopAudioSession(),
            sleepManager: sleepManager,
        )
    }

    // MARK: - Initial State

    @MainActor
    func testInitialState() {
        let draft = makeDraft()
        XCTAssertFalse(draft.isRecording, "New draft should not be recording")
        XCTAssertFalse(draft.isPaused, "New draft should not be paused")
        XCTAssertNil(draft.duration, "New draft should have no duration set")
    }

    // MARK: - Stop Without Starting

    @MainActor
    func testStopRecordingBeforeStart() {
        let sleepManager = MockDeviceSleepManager()
        let draft = makeDraft(sleepManager: sleepManager)

        // Should not crash and duration should remain nil
        draft.stopRecording()

        XCTAssertNil(draft.duration, "Duration should remain nil if recording never started")
        XCTAssertFalse(draft.isPaused)
    }

    @MainActor
    func testStopRecordingAsyncBeforeStart() {
        let draft = makeDraft()

        // Should not crash and duration should remain nil
        draft.stopRecordingAsync()

        XCTAssertNil(draft.duration, "Duration should remain nil if recording never started")
        XCTAssertFalse(draft.isPaused)
    }

    // MARK: - Unavailable Audio Session

    @MainActor
    func testStartRecordingThrowsWhenAudioSessionUnavailable() {
        let draft = makeDraft()
        // NoopAudioSession returns false, so startRecording() should throw.
        XCTAssertThrowsError(try draft.startRecording())
        XCTAssertFalse(draft.isRecording, "Should not be recording after failed start")
        XCTAssertFalse(draft.isPaused, "Should not be paused after failed start")
    }

    // MARK: - Stop Resets Paused State

    @MainActor
    func testStopRecordingResetsPausedFlag() {
        // We can't drive the recorder into a real paused state without a working
        // audio session, so we validate that stopRecording() always leaves isPaused
        // as false regardless of the recorder being nil.
        let draft = makeDraft()
        draft.stopRecording()
        XCTAssertFalse(draft.isPaused, "stopRecording should leave isPaused as false")
    }
}
