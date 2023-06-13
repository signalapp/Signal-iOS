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
                        let sessionStore = self.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.printAllSessions(transaction: transaction)
                    }
                }),
                OWSTableItem(title: "Toggle Key Change", actionBlock: {
                    DebugUISessionState.toggleKeyChange(for: contactThread)
                }),
                OWSTableItem(title: "Delete All Sessions", actionBlock: {
                    self.databaseStorage.write { transaction in
                        let sessionStore = self.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.deleteAllSessions(for: contactThread.contactAddress, transaction: transaction)
                    }
                }),
                OWSTableItem(title: "Archive All Sessions", actionBlock: {
                    self.databaseStorage.write { transaction in
                        let sessionStore = self.signalProtocolStore(for: .aci).sessionStore
                        sessionStore.archiveAllSessions(for: contactThread.contactAddress, transaction: transaction)
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
            OWSTableItem(title: "Clear Session and Identity Store", actionBlock: {
                self.databaseStorage.write { transaction in
                    let sessionStore = self.signalProtocolStore(for: .aci).sessionStore
                    sessionStore.resetSessionStore(transaction)
                    OWSIdentityManager.shared.clearIdentityState(transaction)
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
        Logger.error("Flipping identity Key. Flip again to return.")

        let identityManager = OWSIdentityManager.shared
        let address = thread.contactAddress

        guard let currentKey = identityManager.identityKey(for: address) else { return }

        var flippedKey = Data(count: currentKey.count)
        for i in 0..<flippedKey.count {
            flippedKey[i] = currentKey[i] ^ 0xFF
        }
        owsAssertDebug(flippedKey.count == currentKey.count)
        identityManager.saveRemoteIdentity(flippedKey, address: address)
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
            let name = contactsManager.displayName(for: address)
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
        guard let identity = OWSIdentityManager.shared.recipientIdentity(for: address) else {
            owsFailDebug("No identity for address \(address)")
            return
        }
        let name = contactsManager.displayName(for: address)
        let message = "\(name) is currently marked as \(OWSVerificationStateToString(identity.verificationState))"

        let stateSelection = ActionSheetController(title: "Select a verification state", message: message)
        stateSelection.addAction(OWSActionSheets.cancelAction)

        let allStates: [OWSVerificationState] = [ .verified, .default, .noLongerVerified ]
        allStates.forEach { state in
            stateSelection.addAction(ActionSheetAction(
                title: OWSVerificationStateToString(state),
                handler: { _ in
                    OWSIdentityManager.shared.setVerificationState(
                        state,
                        identityKey: identity.identityKey,
                        address: address,
                        isUserInitiatedChange: false
                    )
                }
            ))
        }

        OWSActionSheets.showActionSheet(stateSelection)
    }
}

#endif
