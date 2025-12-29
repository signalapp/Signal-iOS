//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUISessionState: DebugUIPage {

    let name = "Session State"

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let contactThread = thread as? TSContactThread {
            items += [
                OWSTableItem(title: "Toggle Key Change", actionBlock: {
                    DebugUISessionState.toggleKeyChange(for: contactThread)
                }),
                OWSTableItem(title: "Delete All Sessions", actionBlock: {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.deleteSessions(forServiceId: contactThread.contactAddress.serviceId!, tx: transaction)
                    }
                }),
                OWSTableItem(title: "Archive All Sessions", actionBlock: {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.archiveSessions(forServiceId: contactThread.contactAddress.serviceId!, tx: transaction)
                    }
                }),
            ]
        }

        return OWSTableSection(title: name, items: items)
    }

    // MARK: -

    private static func toggleKeyChange(for thread: TSContactThread) {
        guard let serviceId = thread.contactAddress.serviceId else {
            return
        }
        Logger.error("Flipping identity Key. Flip again to return.")

        let identityManager = DependenciesBridge.shared.identityManager

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            guard let currentKey = identityManager.identityKey(for: SignalServiceAddress(serviceId), tx: tx) else { return }

            var flippedKey = Data(count: currentKey.count)
            for i in 0..<flippedKey.count {
                flippedKey[i] = currentKey[i] ^ 0xFF
            }
            owsAssertDebug(flippedKey.count == currentKey.count)
            identityManager.saveIdentityKey(flippedKey, for: serviceId, tx: tx)
        }
    }
}

#endif
