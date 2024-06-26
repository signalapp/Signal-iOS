//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class CommonCallState {
    let audioActivity: AudioActivity

    init(audioActivity: AudioActivity) {
        self.audioActivity = audioActivity
    }

    deinit {
        owsAssertDebug(systemState != .reported, "call \(localId) was reported to system but never removed")
    }

    // MARK: - Properties

    // Distinguishes between calls locally, e.g. in CallKit
    let localId: UUID = UUID()

    // MARK: - Connected Date

    // Should be used only on the main thread
    private(set) var connectedDate: MonotonicDate? {
        didSet { AssertIsOnMainThread() }
    }

    @discardableResult
    func setConnectedDateIfNeeded() -> Bool {
        guard self.connectedDate == nil else {
            return false
        }
        self.connectedDate = MonotonicDate()
        return true
    }

    // This method should only be called when the call state is "connected".
    func connectionDuration() -> TimeInterval {
        guard let connectedDate else {
            owsFailDebug("Called connectionDuration before connected.")
            return 0
        }
        return TimeInterval(MonotonicDate() - connectedDate) / TimeInterval(NSEC_PER_SEC)
    }

    // MARK: - System OS Interop

    private(set) var systemState: SystemState = .notReported
    enum SystemState {
        case notReported
        case pending
        case reported
        case removed
    }

    func markPendingReportToSystem() {
        owsAssertDebug(systemState == .notReported, "call \(localId) had unexpected system state: \(systemState)")
        systemState = .pending
    }

    func markReportedToSystem() {
        owsAssertDebug(systemState == .notReported || systemState == .pending,
                       "call \(localId) had unexpected system state: \(systemState)")
        systemState = .reported
    }

    func markRemovedFromSystem() {
        // This was an assert that was firing when coming back online after missing
        // a call while offline. See IOS-3416
        if systemState != .reported {
            Logger.warn("call \(localId) had unexpected system state: \(systemState)")
        }
        systemState = .removed
    }
}
