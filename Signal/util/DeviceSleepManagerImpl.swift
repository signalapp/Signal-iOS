//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

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

    init() {
        SwiftSingletons.register(self)
    }

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
