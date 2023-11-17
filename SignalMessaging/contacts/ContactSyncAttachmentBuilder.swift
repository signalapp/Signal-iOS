//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient
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
            owsFailDebug("Could not write contacts sync stream: \(error)")
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
        let threadFinder = ThreadFinder()
        var threadPositions = [Int64: Int]()
        for (inboxPosition, rowId) in try threadFinder.fetchContactSyncThreadRowIds(tx: tx).enumerated() {
            threadPositions[rowId] = inboxPosition + 1 // Row numbers start from 1.
        }

        let localAccount = localAccountToSync(localAddress: localAddress)
        let otherAccounts = isFullSync ? contactsManager.unsortedSignalAccounts(transaction: tx) : []
        let signalAccounts = [localAccount] + otherAccounts.stableSort()

        for signalAccount in signalAccounts {
            try autoreleasepool {
                let contactThread = TSContactThread.getWithContactAddress(signalAccount.recipientAddress, transaction: tx)
                let inboxPosition = contactThread?.sqliteRowId.flatMap { threadPositions.removeValue(forKey: $0) }
                try writeContact(
                    to: contactOutputStream,
                    address: signalAccount.recipientAddress,
                    contactThread: contactThread,
                    signalAccount: signalAccount,
                    inboxPosition: inboxPosition,
                    blockingManager: blockingManager,
                    tx: tx
                )
            }
        }

        if isFullSync {
            for (rowId, inboxPosition) in threadPositions.sorted(by: { $0.key < $1.key }) {
                try autoreleasepool {
                    guard let contactThread = threadFinder.fetch(rowId: rowId, tx: tx) as? TSContactThread else {
                        return
                    }
                    try writeContact(
                        to: contactOutputStream,
                        address: contactThread.contactAddress,
                        contactThread: contactThread,
                        signalAccount: nil,
                        inboxPosition: inboxPosition,
                        blockingManager: blockingManager,
                        tx: tx
                    )
                }
            }
        }
    }

    private static func writeContact(
        to contactOutputStream: ContactOutputStream,
        address: SignalServiceAddress,
        contactThread: TSContactThread?,
        signalAccount: SignalAccount?,
        inboxPosition: Int?,
        blockingManager: BlockingManager,
        tx: SDSAnyReadTransaction
    ) throws {
        let dmStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfiguration = contactThread.map { dmStore.fetchOrBuildDefault(for: .thread($0), tx: tx.asV2Read) }
        let isBlocked = blockingManager.isAddressBlocked(address, transaction: tx)

        try contactOutputStream.writeContact(
            aci: address.serviceId as? Aci,
            phoneNumber: address.e164,
            signalAccount: signalAccount,
            disappearingMessagesConfiguration: dmConfiguration,
            inboxPosition: inboxPosition,
            isBlocked: isBlocked
        )
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
