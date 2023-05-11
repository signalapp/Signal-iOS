//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ContactsUI

extension OWSSyncContactsMessage {

    @objc
    public func buildPlainTextAttachmentFile(transaction: SDSAnyReadTransaction) -> URL? {
        guard let localAddress = tsAccountManager.localAddress else {
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
                recipientUUID: localAddress.uuidString
            )
            signalAccounts.append(localSignalAccount)
        }

        let contactsOutputStream = OWSContactsOutputStream(outputStream: outputStream)
        // We use batching to place an upper bound on memory usage.
        Batching.enumerate(signalAccounts, batchSize: 12) { signalAccount in
            let recipientIdentity: OWSRecipientIdentity? = Self.identityManager.recipientIdentity(for: signalAccount.recipientAddress,
                                                                                                     transaction: transaction)
            let profileKeyData: Data? = Self.profileManager.profileKeyData(for: signalAccount.recipientAddress,
                                                                              transaction: transaction)

            let contactThread = TSContactThread.getWithContactAddress(signalAccount.recipientAddress,
                                                                      transaction: transaction)
            var isArchived: NSNumber?
            var inboxPosition: NSNumber?
            var disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration?
            if let contactThread = contactThread {
                let associatedData = ThreadAssociatedData.fetchOrDefault(for: contactThread,
                                                                            ignoreMissing: false,
                                                                            transaction: transaction)
                isArchived = NSNumber(value: associatedData.isArchived)
                inboxPosition = AnyThreadFinder().sortIndexObjc(thread: contactThread, transaction: transaction)
                disappearingMessagesConfiguration = contactThread.disappearingMessagesConfiguration(with: transaction)
            }
            let isBlocked = blockingManager.isAddressBlocked(signalAccount.recipientAddress, transaction: transaction)

            contactsOutputStream.write(signalAccount,
                                       recipientIdentity: recipientIdentity,
                                       profileKeyData: profileKeyData,
                                       contactsManager: Self.contactsManager,
                                       disappearingMessagesConfiguration: disappearingMessagesConfiguration,
                                       isArchived: isArchived,
                                       inboxPosition: inboxPosition,
                                       isBlocked: isBlocked)
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
