//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUISessionState: DebugUIPage, Dependencies {

    let name = "Session State"

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let contactThread = thread as? TSContactThread {
            items += [
                OWSTableItem(title: "Log All Recipient Identities", actionBlock: {
                    OWSRecipientIdentity.printAllIdentities()
                }),
                OWSTableItem(title: "Log All Sessions", actionBlock: {
                    self.databaseStorage.read { transaction in
                        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.printAll(tx: transaction.asV2Read)
                    }
                }),
                OWSTableItem(title: "Toggle Key Change", actionBlock: {
                    DebugUISessionState.toggleKeyChange(for: contactThread)
                }),
                OWSTableItem(title: "Delete All Sessions", actionBlock: {
                    self.databaseStorage.write { transaction in
                        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.deleteAllSessions(for: contactThread.contactAddress.serviceId!, tx: transaction.asV2Write)
                    }
                }),
                OWSTableItem(title: "Archive All Sessions", actionBlock: {
                    self.databaseStorage.write { transaction in
                        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.archiveAllSessions(for: contactThread.contactAddress.serviceId!, tx: transaction.asV2Write)
                    }
                }),
                OWSTableItem(title: "Send Session Reset", actionBlock: {
                    self.databaseStorage.write { transaction in
                        self.smJobQueues.sessionResetJobQueue.add(contactThread: contactThread, transaction: transaction)
                    }
                })
            ]
        }

        if let groupThread = thread as? TSGroupThread {
            items.append(OWSTableItem(title: "Rotate Sender Key", actionBlock: {
                self.databaseStorage.write { transaction in
                    self.senderKeyStore.resetSenderKeySession(for: groupThread, transaction: transaction)
                }
            }))
        }

        if let thread {
            items.append(OWSTableItem(title: "Update Verification State", actionBlock: {
                DebugUISessionState.updateIdentityVerificationForThread(thread)
            }))
        }

        items += [
            OWSTableItem(title: "Clear Session Store", actionBlock: {
                self.databaseStorage.write { transaction in
                    let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                    sessionStore.resetSessionStore(tx: transaction.asV2Write)
                }
            }),
            OWSTableItem(title: "Clear Sender Key Store", actionBlock: {
                self.databaseStorage.write { transaction in
                    self.senderKeyStore.resetSenderKeyStore(transaction: transaction)
                }
            })
        ]

        return OWSTableSection(title: name, items: items)
    }

    // MARK: -

    private static func toggleKeyChange(for thread: TSContactThread) {
        guard let serviceId = thread.contactAddress.serviceId else {
            return
        }
        Logger.error("Flipping identity Key. Flip again to return.")

        let identityManager = DependenciesBridge.shared.identityManager

        databaseStorage.write { tx in
            guard let currentKey = identityManager.identityKey(for: SignalServiceAddress(serviceId), tx: tx.asV2Read) else { return }

            var flippedKey = Data(count: currentKey.count)
            for i in 0..<flippedKey.count {
                flippedKey[i] = currentKey[i] ^ 0xFF
            }
            owsAssertDebug(flippedKey.count == currentKey.count)
            identityManager.saveIdentityKey(flippedKey, for: serviceId, tx: tx.asV2Write)
        }
    }

    private static func updateIdentityVerificationForThread(_ thread: TSThread) {
        let recipientAddresses = thread.recipientAddressesWithSneakyTransaction

        guard !recipientAddresses.isEmpty else {
            owsFailDebug("No recipients for thread \(thread)")
            return
        }

        if recipientAddresses.count == 1, let address = recipientAddresses.first {
            updateIdentityVerificationForAddress(address)
            return
        }

        let recipientSelection = ActionSheetController(title: "Select a recipient")
        recipientSelection.addAction(OWSActionSheets.cancelAction)

        recipientAddresses.forEach { address in
            let name = databaseStorage.read { tx in contactsManager.displayName(for: address, transaction: tx) }
            recipientSelection.addAction(ActionSheetAction(
                title: name,
                handler: { _ in
                    DebugUISessionState.updateIdentityVerificationForAddress(address)
                }
            ))
        }

        OWSActionSheets.showActionSheet(recipientSelection)
    }

    private static func updateIdentityVerificationForAddress(_ address: SignalServiceAddress) {
        let identityManager = DependenciesBridge.shared.identityManager
        guard let identity = databaseStorage.read(block: { tx in identityManager.recipientIdentity(for: address, tx: tx.asV2Read) }) else {
            owsFailDebug("No identity for address \(address)")
            return
        }
        let name = databaseStorage.read { tx in contactsManager.displayName(for: address, transaction: tx) }
        let message = "\(name) is currently marked as \(OWSVerificationStateToString(identity.verificationState))"

        let stateSelection = ActionSheetController(title: "Select a verification state", message: message)
        stateSelection.addAction(OWSActionSheets.cancelAction)

        let allStates: [VerificationState] = [
            .verified,
            .implicit(isAcknowledged: false),
            .implicit(isAcknowledged: true),
            .noLongerVerified
        ]
        allStates.forEach { state in
            stateSelection.addAction(ActionSheetAction(
                title: "\(state)",
                handler: { _ in
                    databaseStorage.write { tx in
                        _ = identityManager.setVerificationState(
                            state,
                            of: identity.identityKey,
                            for: address,
                            isUserInitiatedChange: false,
                            tx: tx.asV2Write
                        )
                    }
                }
            ))
        }

        OWSActionSheets.showActionSheet(stateSelection)
    }
}

#endif
