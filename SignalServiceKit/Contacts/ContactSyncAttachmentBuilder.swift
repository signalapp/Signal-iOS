//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient

enum ContactSyncAttachmentBuilder {
    static func buildAttachmentFile(
        contactsManager: OWSContactsManager,
        tx: DBReadTransaction
    ) -> URL? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
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
                localAddress: localAddress,
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
        localAddress: SignalServiceAddress,
        contactsManager: OWSContactsManager,
        tx: DBReadTransaction
    ) throws {
        let threadFinder = ThreadFinder()
        var threadPositions = [Int64: Int]()
        for (inboxPosition, rowId) in try threadFinder.fetchContactSyncThreadRowIds(tx: tx).enumerated() {
            threadPositions[rowId] = inboxPosition + 1 // Row numbers start from 1.
        }

        let localAccount = localAccountToSync(localAddress: localAddress)
        let otherAccounts = SignalAccount.anyFetchAll(transaction: tx)
        let signalAccounts = [localAccount] + otherAccounts.sorted(
            by: { ($0.recipientPhoneNumber ?? "") < ($1.recipientPhoneNumber ?? "") }
        )

        // De-duplicate threads by their address. This de-duping works correctly
        // because we no longer allow stale information on TSThreads and removed
        // all existing stale information via removeRedundantPhoneNumbers.
        var seenAddresses = Set<SignalServiceAddress>()

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

        for signalAccount in signalAccounts {
            try autoreleasepool {
                guard let phoneNumber = signalAccount.recipientPhoneNumber else {
                    return
                }
                let signalRecipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx)
                guard let signalRecipient else {
                    return
                }
                let contactThread = TSContactThread.getWithContactAddress(signalRecipient.address, transaction: tx)
                let inboxPosition = contactThread?.sqliteRowId.flatMap { threadPositions.removeValue(forKey: $0) }
                try writeContact(
                    to: contactOutputStream,
                    address: signalRecipient.address,
                    contactThread: contactThread,
                    signalAccount: signalAccount,
                    inboxPosition: inboxPosition,
                    tx: tx
                )
                seenAddresses.insert(signalRecipient.address)
            }
        }

        for (rowId, inboxPosition) in threadPositions.sorted(by: { $0.key < $1.key }) {
            try autoreleasepool {
                guard let contactThread = threadFinder.fetch(rowId: rowId, tx: tx) as? TSContactThread else {
                    return
                }
                guard seenAddresses.insert(contactThread.contactAddress).inserted else {
                    Logger.warn("Skipping duplicate thread for \(contactThread.contactAddress)")
                    return
                }
                try writeContact(
                    to: contactOutputStream,
                    address: contactThread.contactAddress,
                    contactThread: contactThread,
                    signalAccount: nil,
                    inboxPosition: inboxPosition,
                    tx: tx
                )
            }
        }
    }

    private static func writeContact(
        to contactOutputStream: ContactOutputStream,
        address: SignalServiceAddress,
        contactThread: TSContactThread?,
        signalAccount: SignalAccount?,
        inboxPosition: Int?,
        tx: DBReadTransaction
    ) throws {
        let dmStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfiguration = contactThread.map { dmStore.fetchOrBuildDefault(for: .thread($0), tx: tx) }

        try contactOutputStream.writeContact(
            aci: address.serviceId as? Aci,
            phoneNumber: address.e164,
            signalAccount: signalAccount,
            disappearingMessagesConfiguration: dmConfiguration,
            inboxPosition: inboxPosition
        )
    }

    private static func localAccountToSync(localAddress: SignalServiceAddress) -> SignalAccount {
        // OWSContactsOutputStream requires all signalAccount to have a contact.
        return SignalAccount(
            recipientPhoneNumber: localAddress.phoneNumber,
            recipientServiceId: localAddress.serviceId,
            multipleAccountLabelText: nil,
            cnContactId: nil,
            givenName: "",
            familyName: "",
            nickname: "",
            fullName: "",
            contactAvatarHash: nil,
        )
    }
}

final private class OWSStreamDelegate: NSObject, StreamDelegate {
    private let _hadError = AtomicBool(false, lock: .sharedGlobal)
    public var hadError: Bool { _hadError.get() }

    @objc
    public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        if eventCode == .errorOccurred {
            _hadError.set(true)
        }
    }
}
