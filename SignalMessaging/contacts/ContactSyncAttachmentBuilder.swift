//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import SignalCoreKit
import SignalServiceKit

enum ContactSyncAttachmentBuilder {
    static func buildAttachmentFile(
        for contactSyncMessage: OWSSyncContactsMessage,
        blockingManager: BlockingManager,
        contactsManager: OWSContactsManager,
        tx: SDSAnyReadTransaction
    ) -> URL? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localAddress = tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
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

        do {
            defer {
                outputStream.remove(from: .current, forMode: .default)
                outputStream.close()
            }
            try fetchAndWriteContacts(
                to: ContactOutputStream(outputStream: outputStream),
                isFullSync: contactSyncMessage.isFullSync,
                localAddress: localAddress,
                blockingManager: blockingManager,
                contactsManager: contactsManager,
                tx: tx
            )
        } catch {
            owsFailDebug("Could not write contacts sync stream.")
            return nil
        }

        guard outputStream.streamStatus == .closed, !outputStreamDelegate.hadError else {
            owsFailDebug("Could not close stream.")
            return nil
        }

        return fileUrl
    }

    private static func fetchAndWriteContacts(
        to contactOutputStream: ContactOutputStream,
        isFullSync: Bool,
        localAddress: SignalServiceAddress,
        blockingManager: BlockingManager,
        contactsManager: OWSContactsManager,
        tx: SDSAnyReadTransaction
    ) throws {
        var signalAccounts = isFullSync ? contactsManager.unsortedSignalAccounts(transaction: tx) : []
        signalAccounts.append(localAccountToSync(localAddress: localAddress))

        for signalAccount in signalAccounts {
            try autoreleasepool {
                let contactThread = TSContactThread.getWithContactAddress(signalAccount.recipientAddress, transaction: tx)
                var inboxPosition: Int64?
                var dmConfiguration: OWSDisappearingMessagesConfiguration?
                if let contactThread {
                    inboxPosition = try? ThreadFinder().sortIndex(thread: contactThread, transaction: tx)
                    let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(contactThread), tx: tx.asV2Read)
                }
                let isBlocked = blockingManager.isAddressBlocked(signalAccount.recipientAddress, transaction: tx)

                try contactOutputStream.writeContact(
                    signalAccount: signalAccount,
                    contactsManager: contactsManager,
                    disappearingMessagesConfiguration: dmConfiguration,
                    inboxPosition: inboxPosition,
                    isBlocked: isBlocked
                )
            }
        }
    }

    private static func localAccountToSync(localAddress: SignalServiceAddress) -> SignalAccount {
        // OWSContactsOutputStream requires all signalAccount to have a contact.
        let contact = Contact(systemContact: CNContact())
        return SignalAccount(contact: contact, address: localAddress)
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
