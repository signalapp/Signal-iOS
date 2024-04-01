//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/**
 * Archives a contact (``SignalRecipient``) as a ``BackupProtoContact``, which is a type of
 * ``BackupProtoRecipient``.
 */
public class MessageBackupContactRecipientArchiver: MessageBackupRecipientDestinationArchiver {

    private let blockingManager: MessageBackup.Shims.BlockingManager
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientHidingManager: RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let storyStore: StoryStore
    private let tsAccountManager: TSAccountManager

    public init(
        blockingManager: MessageBackup.Shims.BlockingManager,
        profileManager: MessageBackup.Shims.ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientHidingManager: RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        storyStore: StoryStore,
        tsAccountManager: TSAccountManager
    ) {
        self.blockingManager = blockingManager
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
        self.storyStore = storyStore
        self.tsAccountManager = tsAccountManager
    }

    private typealias ArchivingAddress = MessageBackup.RecipientArchivingContext.Address

    public func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        let whitelistedAddresses = Set(profileManager.allWhitelistedRegisteredAddresses(tx: tx))
        let blockedAddresses = blockingManager.blockedAddresses(tx: tx)

        var errors = [ArchiveMultiFrameResult.ArchiveFrameError]()

        recipientDatabaseTable.enumerateAll(tx: tx) { recipient in
            guard
                let contactAddress = MessageBackup.ContactAddress(
                    aci: recipient.aci,
                    pni: recipient.pni,
                    e164: E164(recipient.phoneNumber?.stringValue)
                )
            else {
                // Skip but don't add to the list of errors.
                Logger.warn("Skipping empty recipient")
                return
            }
            let recipientAddress = contactAddress.asArchivingAddress()

            let recipientId = context.assignRecipientId(to: recipientAddress)

            var unregisteredAtTimestamp: UInt64 = 0
            if !recipient.isRegistered {
                unregisteredAtTimestamp = (
                    recipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp
                )
            }

            let storyContext = recipient.aci.map { self.storyStore.getOrCreateStoryContextAssociatedData(for: $0, tx: tx) }

            var contact = BackupProtoContact(
                blocked: blockedAddresses.contains(recipient.address),
                hidden: self.recipientHidingManager.isHiddenRecipient(recipient, tx: tx),
                unregisteredTimestamp: unregisteredAtTimestamp,
                profileSharing: whitelistedAddresses.contains(recipient.address),
                hideStory: storyContext?.isHidden ?? false
            )

            contact.registered = recipient.isRegistered ? .REGISTERED : .NOT_REGISTERED
            contact.aci = recipient.aci.map(\.rawUUID.data)
            contact.pni = recipient.pni.map(\.rawUUID.data)
            contact.e164 = recipient.address.e164.map(\.uint64Value)
            // TODO: username?

            let userProfile = self.profileManager.getUserProfile(for: recipient.address, tx: tx)
            contact.profileKey = userProfile?.profileKey.map(\.keyData)
            contact.profileGivenName = userProfile?.givenName
            contact.profileFamilyName = userProfile?.familyName
            // TODO: joined name?

            Self.writeFrameToStream(
                stream,
                objectId: .contact(contactAddress),
                frameBuilder: {
                    var recipient = BackupProtoRecipient(id: recipientId.value)
                    recipient.destination = .contact(contact)

                    var frame = BackupProtoFrame()
                    frame.item = .recipient(recipient)
                    return frame
                }
            ).map { errors.append($0) }
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    static func canRestore(_ recipient: BackupProtoRecipient) -> Bool {
        switch recipient.destination {
        case .contact:
            return true
        case nil, .group, .distributionList, .selfRecipient, .releaseNotes:
            return false
        }
    }

    public func restore(
        _ recipientProto: BackupProtoRecipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        let contactProto: BackupProtoContact
        switch recipientProto.destination {
        case .contact(let backupProtoContact):
            contactProto = backupProtoContact
        case nil, .group, .distributionList, .selfRecipient, .releaseNotes:
            return .failure(
                [.developerError(
                    recipientProto.recipientId,
                    OWSAssertionError("Invalid proto for class")
                )]
            )
        }

        let isRegistered: Bool?
        let unregisteredTimestamp: UInt64?
        switch contactProto.registered {
        case nil, .UNKNOWN:
            isRegistered = nil
            unregisteredTimestamp = nil
        case .REGISTERED:
            isRegistered = true
            unregisteredTimestamp = nil
        case .NOT_REGISTERED:
            isRegistered = false
            unregisteredTimestamp = contactProto.unregisteredTimestamp
        }

        let aci: Aci?
        let pni: Pni?
        let e164: E164?
        if let aciRaw = contactProto.aci {
            guard let aciUuid = UUID(data: aciRaw) else {
                return .failure(
                    [.invalidProtoData(
                        recipientProto.recipientId,
                        .invalidAci(protoClass: BackupProtoContact.self)
                    )]
                )
            }
            aci = Aci.init(fromUUID: aciUuid)
        } else {
            aci = nil
        }
        if let pniRaw = contactProto.pni {
            guard let pniUuid = UUID(data: pniRaw) else {
                return .failure(
                    [.invalidProtoData(
                        recipientProto.recipientId,
                        .invalidPni(protoClass: BackupProtoContact.self)
                    )]
                )
            }
            pni = Pni.init(fromUUID: pniUuid)
        } else {
            pni = nil
        }
        if let contactProtoE164 = contactProto.e164 {
            guard let protoE164 = E164(contactProtoE164) else {
                return .failure(
                    [.invalidProtoData(
                        recipientProto.recipientId,
                        .invalidE164(protoClass: BackupProtoContact.self)
                    )]
                )
            }
            e164 = protoE164
        } else {
            e164 = nil
        }

        guard
            let address = MessageBackup.ContactAddress(aci: aci, pni: pni, e164: e164)
        else {
            // Need at least one identifier!
            return .failure(
                [.invalidProtoData(
                    recipientProto.recipientId,
                    .contactWithoutIdentifiers
                )]
            )
        }
        context[recipientProto.recipientId] = .contact(address)

        var recipient = SignalRecipient.fromBackup(
            address,
            isRegistered: isRegistered,
            unregisteredAtTimestamp: unregisteredTimestamp
        )

        // TODO: remove this check; we should be starting with an empty database.
        if let existingRecipient = recipientDatabaseTable.fetchRecipient(address: recipient.address, tx: tx) {
            recipient = existingRecipient
            if isRegistered == true, !recipient.isRegistered {
                recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: false, tx: tx)
            } else if isRegistered == false, recipient.isRegistered, let unregisteredTimestamp {
                recipientManager.markAsUnregisteredAndSave(
                    recipient,
                    unregisteredAt: .specificTimeFromOtherDevice(unregisteredTimestamp),
                    shouldUpdateStorageService: false,
                    tx: tx
                )
            }
        } else {
            recipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        }

        if contactProto.profileSharing {
            // Add to the whitelist.
            profileManager.addToWhitelist(recipient.address, tx: tx)
        }

        if contactProto.blocked {
            blockingManager.addBlockedAddress(recipient.address, tx: tx)
        }

        if contactProto.hidden {
            do {
                try recipientHidingManager.addHiddenRecipient(recipient, wasLocallyInitiated: false, tx: tx)
            } catch let error {
                return .failure([.databaseInsertionFailed(recipientProto.recipientId, error)])
            }
        }

        // We only need to active hide, since unhidden is the default.
        if contactProto.hideStory, let aci = address.aci {
            let storyContext = storyStore.getOrCreateStoryContextAssociatedData(for: aci, tx: tx)
            storyStore.updateStoryContext(storyContext, isHidden: true, tx: tx)
        }

        profileManager.setProfileGivenName(
            givenName: contactProto.profileGivenName,
            familyName: contactProto.profileFamilyName,
            profileKey: contactProto.profileKey,
            address: recipient.address,
            tx: tx
        )

        return .success
    }
}
