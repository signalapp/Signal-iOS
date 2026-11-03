//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

/// This entity is responsible for keeping the screen on if certain
/// behaviors (e.g., recording or playing voice messages) are in progress.
///
/// Sleep blocking is achieved by using "block objects". For example, the
/// audio player will add/remove a "block object" when it starts/stops. If
/// there are any active "block objects", the device won't sleep. After they
/// are all removed, the device will be able to sleep.
class DeviceSleepManagerImpl: DeviceSleepManager {
    @MainActor
    private var blockObjects = [Weak<DeviceSleepBlockObject>]()

    init() {}

    @MainActor
    func addBlock(blockObject: DeviceSleepBlockObject) {
        Logger.info("Adding sleep block: \(blockObject.blockReason)")
        blockObjects.append(Weak(value: blockObject))
        ensureSleepBlocking()
    }

    @MainActor
    func removeBlock(blockObject: DeviceSleepBlockObject) {
        Logger.info("Removing sleep block: \(blockObject.blockReason)")
        blockObjects.removeAll(where: { $0.value === blockObject })
        ensureSleepBlocking()
    }

    @MainActor
    private func ensureSleepBlocking() {
        // Cull expired blocks.
        if blockObjects.contains(where: { $0.value == nil }) {
            owsFailDebug("Callers must remove BlockObjects explicitly.")
            blockObjects.removeAll(where: { $0.value == nil })
        }

        let blockObjects = self.blockObjects.compactMap(\.value)

        let shouldBeBlocking = !blockObjects.isEmpty
        if UIApplication.shared.isIdleTimerDisabled != shouldBeBlocking {
            if shouldBeBlocking {
                Logger.info("Blocking sleep.")
            } else {
                Logger.info("Unblocking sleep.")
            }
        }
        UIApplication.shared.isIdleTimerDisabled = shouldBeBlocking
    }
}

// MARK: -

/// Blocks device sleep while toggled on, for at most `maxBlockDuration`. Once
/// expired, sleep isn't blocked again until this is toggled off and back on.
@MainActor
final class DeviceSleepBlocker {
    private enum State {
        case blocking(DeviceSleepBlockObject, expirationTask: Task<Void, Never>)
        case expired
    }

    private let blockReason: String
    private let maxBlockDuration: TimeInterval
    private let deviceSleepManager: DeviceSleepManager
    private let sleepFn: @MainActor (TimeInterval) async throws -> Void

    private var state: State?

    init(
        blockReason: String,
        maxBlockDuration: TimeInterval,
        deviceSleepManager: DeviceSleepManager,
        sleepFn: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0.clampedNanoseconds)
        },
    ) {
        self.blockReason = blockReason
        self.maxBlockDuration = maxBlockDuration
        self.deviceSleepManager = deviceSleepManager
        self.sleepFn = sleepFn
    }

    func setShouldBlock(_ shouldBlock: Bool) {
        if shouldBlock {
            switch state {
            case .blocking, .expired:
                break
            case nil:
                let blockObject = DeviceSleepBlockObject(blockReason: blockReason)
                deviceSleepManager.addBlock(blockObject: blockObject)

                let expirationTask = Task { [weak self, sleepFn, maxBlockDuration] in
                    try? await sleepFn(maxBlockDuration)
                    guard !Task.isCancelled else { return }
                    self?.expire()
                }
                state = .blocking(blockObject, expirationTask: expirationTask)
            }
        } else {
            switch state {
            case nil, .expired:
                break
            case .blocking(let blockObject, let expirationTask):
                expirationTask.cancel()
                deviceSleepManager.removeBlock(blockObject: blockObject)
            }
            state = nil
        }
    }

    private func expire() {
        switch state {
        case nil, .expired:
            break
        case .blocking(let blockObject, _):
            deviceSleepManager.removeBlock(blockObject: blockObject)
            state = .expired
        }
    }

#if TESTABLE_BUILD
    var expirationTaskForTesting: Task<Void, Never>? {
        switch state {
        case nil, .expired: nil
        case .blocking(_, let expirationTask): expirationTask
        }
    }
#endif
}
