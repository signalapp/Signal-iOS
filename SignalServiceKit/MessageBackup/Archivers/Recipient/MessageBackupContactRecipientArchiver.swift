//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Archives ``SignalRecipient``s as ``BackupProto_Contact`` recipients.
public class MessageBackupContactRecipientArchiver: MessageBackupProtoArchiver {
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<RecipientId>

    private let blockingManager: MessageBackup.Shims.BlockingManager
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientHidingManager: RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let signalServiceAddressCache: SignalServiceAddressCache
    private let storyStore: StoryStore
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager

    public init(
        blockingManager: MessageBackup.Shims.BlockingManager,
        profileManager: MessageBackup.Shims.ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientHidingManager: RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        signalServiceAddressCache: SignalServiceAddressCache,
        storyStore: StoryStore,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager
    ) {
        self.blockingManager = blockingManager
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
        self.signalServiceAddressCache = signalServiceAddressCache
        self.storyStore = storyStore
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
    }

    func archiveAllContactRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        let whitelistedAddresses = Set(profileManager.allWhitelistedAddresses(tx: tx))
        let blockedAddresses = blockingManager.blockedAddresses(tx: tx)

        var errors = [ArchiveFrameError]()

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

            guard !context.localIdentifiers.containsAnyOf(
                aci: recipient.aci,
                phoneNumber: E164(recipient.phoneNumber?.stringValue),
                pni: recipient.pni
            ) else {
                // Skip local user
                return
            }

            let recipientAddress = contactAddress.asArchivingAddress()

            let recipientId = context.assignRecipientId(to: recipientAddress)

            let storyContext = recipient.aci.map { self.storyStore.getOrCreateStoryContextAssociatedData(for: $0, tx: tx) }

            var contact = BackupProto_Contact()
            contact.blocked = blockedAddresses.contains(recipient.address)
            contact.visibility = { () -> BackupProto_Contact.Visibility in
                if self.recipientHidingManager.isHiddenRecipient(recipient, tx: tx) {
                    if
                        let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx),
                        threadStore.hasPendingMessageRequest(thread: contactThread, tx: tx)
                    {
                        return .hiddenMessageRequest
                    }

                    return .hidden
                } else {
                    return .visible
                }
            }()
            contact.profileSharing = whitelistedAddresses.contains(recipient.address)
            contact.hideStory = storyContext?.isHidden ?? false
            contact.registration = { () -> BackupProto_Contact.OneOf_Registration in
                if !recipient.isRegistered {
                    var notRegistered = BackupProto_Contact.NotRegistered()
                    notRegistered.unregisteredTimestamp = recipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp

                    return .notRegistered(notRegistered)
                }

                return .registered(BackupProto_Contact.Registered())
            }()

            if let aci = recipient.aci {
                contact.aci = aci.rawUUID.data

                if let username = usernameLookupManager.fetchUsername(forAci: aci, transaction: tx) {
                    contact.username = username
                }
            }
            if let pni = recipient.pni {
                contact.pni = pni.rawUUID.data
            }
            if
                let phoneNumberString = recipient.phoneNumber?.stringValue,
                let phoneNumberUInt = E164(phoneNumberString)?.uint64Value
            {
                contact.e164 = phoneNumberUInt
            }

            let userProfile = self.profileManager.getUserProfile(for: recipient.address, tx: tx)
            if let profileKey = userProfile?.profileKey {
                contact.profileKey = profileKey.keyData
            }
            if let givenName = userProfile?.givenName {
                contact.profileGivenName = givenName
            }
            if let familyName = userProfile?.familyName {
                contact.profileFamilyName = familyName
            }

            Self.writeFrameToStream(
                stream,
                objectId: .contact(contactAddress),
                frameBuilder: {
                    var recipient = BackupProto_Recipient()
                    recipient.id = recipientId.value
                    recipient.destination = .contact(contact)

                    var frame = BackupProto_Frame()
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

    func restoreContactRecipientProto(
        _ contactProto: BackupProto_Contact,
        recipient: BackupProto_Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, recipient.recipientId, line: line)])
        }

        let isRegistered: Bool
        let unregisteredTimestamp: UInt64?
        switch contactProto.registration {
        case nil:
            return .failure([.restoreFrameError(
                .invalidProtoData(.contactWithoutRegistrationInfo),
                recipient.recipientId
            )])
        case .notRegistered(let notRegisteredProto):
            isRegistered = false
            unregisteredTimestamp = notRegisteredProto.unregisteredTimestamp
        case .registered:
            isRegistered = true
            unregisteredTimestamp = nil
        }

        let aci: Aci?
        let pni: Pni?
        let e164: E164?
        let profileKey: Aes256Key?
        if contactProto.hasAci {
            guard let aciUuid = UUID(data: contactProto.aci) else {
                return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Contact.self)))
            }
            aci = Aci.init(fromUUID: aciUuid)
        } else {
            aci = nil
        }
        if contactProto.hasPni {
            guard let pniUuid = UUID(data: contactProto.pni) else {
                return restoreFrameError(.invalidProtoData(.invalidPni(protoClass: BackupProto_Contact.self)))
            }
            pni = Pni.init(fromUUID: pniUuid)
        } else {
            pni = nil
        }
        if contactProto.hasE164 {
            guard let protoE164 = E164(contactProto.e164) else {
                return restoreFrameError(.invalidProtoData(.invalidE164(protoClass: BackupProto_Contact.self)))
            }
            e164 = protoE164
        } else {
            e164 = nil
        }
        if contactProto.hasProfileKey {
            guard let protoProfileKey = Aes256Key(data: contactProto.profileKey) else {
                return restoreFrameError(.invalidProtoData(.invalidProfileKey(protoClass: BackupProto_Contact.self)))
            }
            profileKey = protoProfileKey
        } else {
            profileKey = nil
        }

        /// This check will fail if all these identifiers are `nil`.
        guard let backupContactAddress = MessageBackup.ContactAddress(
            aci: aci,
            pni: pni,
            e164: e164
        ) else {
            return restoreFrameError(.invalidProtoData(.contactWithoutIdentifiers))
        }
        context[recipient.recipientId] = .contact(backupContactAddress)

        let recipient = SignalRecipient.fromBackup(
            backupContactAddress,
            isRegistered: isRegistered,
            unregisteredAtTimestamp: unregisteredTimestamp
        )

        // Stop early if this is the local user. That shouldn't happen.
        let profileInsertableAddress: OWSUserProfile.InsertableAddress
        if let serviceId = backupContactAddress.aci ?? backupContactAddress.pni {
            profileInsertableAddress = OWSUserProfile.insertableAddress(
                serviceId: serviceId,
                localIdentifiers: context.localIdentifiers
            )
        } else if let phoneNumber = backupContactAddress.e164 {
            profileInsertableAddress = OWSUserProfile.insertableAddress(
                legacyPhoneNumberFromBackupRestore: phoneNumber,
                localIdentifiers: context.localIdentifiers
            )
        } else {
            return restoreFrameError(.developerError(OWSAssertionError("How did we have no identifiers after constructing a backup contact address?")))
        }
        switch profileInsertableAddress {
        case .localUser:
            return restoreFrameError(.invalidProtoData(.otherContactWithLocalIdentifiers))
        case .otherUser, .legacyUserPhoneNumberFromBackupRestore:
            break
        }

        recipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        /// No Backup code should be relying on the SSA cache, but once we've
        /// finished restoring and launched we want the cache to have accurate
        /// mappings based on the recipients we just restored.
        signalServiceAddressCache.updateRecipient(recipient, tx: tx)

        if
            let aci = recipient.aci,
            contactProto.hasUsername
        {
            usernameLookupManager.saveUsername(contactProto.username, forAci: aci, transaction: tx)
        }

        if contactProto.profileSharing {
            // Add to the whitelist.
            profileManager.addToWhitelist(recipient.address, tx: tx)
        }

        if contactProto.blocked {
            blockingManager.addBlockedAddress(recipient.address, tx: tx)
        }

        switch contactProto.visibility {
        case .hidden, .hiddenMessageRequest:
            /// Message-request state for hidden recipients isn't explicitly
            /// tracked on iOS, and instead is derived from their hidden state
            /// and the most-recent interactions in their 1:1 chat. So, for both
            /// of these cases all we need to do is hide the recipient.
            do {
                try recipientHidingManager.addHiddenRecipient(recipient, wasLocallyInitiated: false, tx: tx)
            } catch let error {
                return restoreFrameError(.databaseInsertionFailed(error))
            }
        case .visible, .UNRECOGNIZED:
            break
        }

        // We only need to active hide, since unhidden is the default.
        if contactProto.hideStory, let aci = backupContactAddress.aci {
            let storyContext = storyStore.getOrCreateStoryContextAssociatedData(for: aci, tx: tx)
            storyStore.updateStoryContext(storyContext, updateStorageService: false, isHidden: true, tx: tx)
        }

        profileManager.upsertOtherUserProfile(
            insertableAddress: profileInsertableAddress,
            givenName: contactProto.profileGivenName,
            familyName: contactProto.profileFamilyName,
            profileKey: profileKey,
            tx: tx
        )

        // TODO: [Backups] Enqueue a fetch of this contact's profile and download of their avatar (even if we have no profile key).

        return .success
    }
}
