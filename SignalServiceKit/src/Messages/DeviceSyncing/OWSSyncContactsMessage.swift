//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ContactsUI

extension OWSSyncContactsMessage {

    @objc
    public func buildPlainTextAttachmentFile(transaction tx: SDSAnyReadTransaction) -> URL? {
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }

        let fileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        guard let outputStream = OutputStream(url: fileUrl, append: false) else {
            owsFailDebug("Could not open outputStream.")
            return nil
        }
        let outputStreamDelegate = OWSStreamDelegate()
        outputStream.delegate = outputStreamDelegate
        outputStream.schedule(in: .current, forMode: .default)
        outputStream.open()
        guard outputStream.streamStatus == .open else {
            owsFailDebug("Could not open outputStream.")
            return nil
        }

        func closeOutputStream() {
            outputStream.remove(from: .current, forMode: .default)
            outputStream.close()
        }

        var signalAccounts = self.signalAccounts

        let hasLocalAddress = !signalAccounts.filter { $0.recipientAddress.isLocalAddress }.isEmpty
        if !hasLocalAddress {
            // OWSContactsOutputStream requires all signalAccount to have a contact.
            let localContact = Contact(systemContact: CNContact())
            let localSignalAccount = SignalAccount(
                contact: localContact,
                contactAvatarHash: nil,
                multipleAccountLabelText: nil,
                recipientPhoneNumber: localAddress.phoneNumber,
                recipientServiceId: localAddress.aci
            )
            signalAccounts.append(localSignalAccount)
        }

        let contactsOutputStream = OWSContactsOutputStream(outputStream: outputStream)
        // We use batching to place an upper bound on memory usage.
        for signalAccount in signalAccounts {
            autoreleasepool {
                let contactThread = TSContactThread.getWithContactAddress(signalAccount.recipientAddress, transaction: tx)
                var inboxPosition: NSNumber?
                var dmConfiguration: OWSDisappearingMessagesConfiguration?
                if let contactThread {
                    inboxPosition = try? ThreadFinder().sortIndex(thread: contactThread, transaction: tx)
                        .map { NSNumber(value: $0) }
                    let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(contactThread), tx: tx.asV2Read)
                }
                let isBlocked = blockingManager.isAddressBlocked(signalAccount.recipientAddress, transaction: tx)

                contactsOutputStream.write(
                    signalAccount,
                    contactsManager: Self.contactsManager,
                    disappearingMessagesConfiguration: dmConfiguration,
                    inboxPosition: inboxPosition,
                    isBlocked: isBlocked
                )
            }
        }

        closeOutputStream()

        guard !contactsOutputStream.hasError else {
            owsFailDebug("Could not write contacts sync stream.")
            return nil
        }
        guard outputStream.streamStatus == .closed,
              !outputStreamDelegate.hadError else {
                  owsFailDebug("Could not close stream.")
                  return nil
              }

        return fileUrl
    }
}

private class OWSStreamDelegate: NSObject, StreamDelegate {
    private let _hadError = AtomicBool(false)
    public var hadError: Bool { _hadError.get() }

    @objc
    public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        if eventCode == .errorOccurred {
            _hadError.set(true)
        }
    }
}
