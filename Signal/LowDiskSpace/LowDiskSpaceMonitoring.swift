//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Responsible for continuously monitoring for "critically low disk space" in
/// the main app, and terminating the process if detected.
class LowDiskSpaceMonitoringManager {
    private struct State {
        var monitoringTask: Task<Void, Never>?
    }

    private let lowDiskSpaceManager: LowDiskSpaceManager

    private let monitoringInterval: TimeInterval
    private let state = AtomicValue(State(), lock: .init())

    init(
        lowDiskSpaceManager: LowDiskSpaceManager,
        monitoringInterval: TimeInterval,
    ) {
        self.lowDiskSpaceManager = lowDiskSpaceManager
        self.monitoringInterval = monitoringInterval
    }

    func start() {
        state.update { _state in
            owsPrecondition(
                _state.monitoringTask == nil,
                "Attempted to start monitoring multiple times!",
            )

            _state.monitoringTask = Task {
                await continuouslyMonitorDiskSpace()
            }
        }
    }

    private func continuouslyMonitorDiskSpace() async {
        while true {
            if lowDiskSpaceManager.isDiskSpaceCriticallyLow() {
                owsFail("Disk space is critically low; crashing.")
            }

            do {
                try await Task.sleep(nanoseconds: monitoringInterval.clampedNanoseconds)
            } catch {
                return
            }
        }
    }
}
