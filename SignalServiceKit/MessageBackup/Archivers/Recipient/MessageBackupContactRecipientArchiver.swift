//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

/// Archives ``SignalRecipient``s as ``BackupProto_Contact`` recipients.
public class MessageBackupContactRecipientArchiver: MessageBackupProtoArchiver {
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<RecipientId>

    private let avatarFetcher: MessageBackupAvatarFetcher
    private let blockingManager: MessageBackup.Shims.BlockingManager
    private let dateProvider: DateProvider
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let recipientHidingManager: RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let recipientStore: MessageBackupRecipientStore
    private let signalServiceAddressCache: SignalServiceAddressCache
    private let storyStore: MessageBackupStoryStore
    private let threadStore: MessageBackupThreadStore
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager

    public init(
        avatarFetcher: MessageBackupAvatarFetcher,
        blockingManager: MessageBackup.Shims.BlockingManager,
        dateProvider: @escaping DateProvider,
        profileManager: MessageBackup.Shims.ProfileManager,
        recipientHidingManager: RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        recipientStore: MessageBackupRecipientStore,
        signalServiceAddressCache: SignalServiceAddressCache,
        storyStore: MessageBackupStoryStore,
        threadStore: MessageBackupThreadStore,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager
    ) {
        self.avatarFetcher = avatarFetcher
        self.blockingManager = blockingManager
        self.dateProvider = dateProvider
        self.profileManager = profileManager
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
        self.recipientStore = recipientStore
        self.signalServiceAddressCache = signalServiceAddressCache
        self.storyStore = storyStore
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
    }

    // MARK: -

    func archiveAllContactRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        let whitelistedAddresses = Set(profileManager.allWhitelistedAddresses(tx: context.tx))
        let blockedAddresses = blockingManager.blockedAddresses(tx: context.tx)

        var errors = [ArchiveFrameError]()

        func writeToStream(
            contact: BackupProto_Contact,
            contactAddress: MessageBackup.ContactAddress
        ) {
            let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
                stream,
                objectId: .contact(contactAddress),
                frameBuilder: {
                    let recipientAddress = contactAddress.asArchivingAddress()
                    let recipientId = context.assignRecipientId(to: recipientAddress)

                    var recipient = BackupProto_Recipient()
                    recipient.id = recipientId.value
                    recipient.destination = .contact(contact)

                    var frame = BackupProto_Frame()
                    frame.item = .recipient(recipient)
                    return frame
                }
            )

            if let maybeError {
                errors.append(maybeError)
            }
        }

        /// Track all the `ServiceId`s that we've archived, so we don't attempt
        /// to archive a `Contact` frame twice for the same service ID.
        var archivedServiceIds = Set<ServiceId>()
        /// Track all the phone numbers we've archived too, so we don't attempt to archive a
        /// `Contact` twice for the same e164.
        var archivedPhoneNumbers = Set<String>()

        /// First, we enumerate all `SignalRecipient`s, which are our "primary
        /// key" for contacts. They directly contain many of the fields we store
        /// in a `Contact` recipient, with the other fields keyed off data in
        /// the recipient.
        let recipientBlock: (SignalRecipient) -> Void = { recipient in
            guard
                let contactAddress = MessageBackup.ContactAddress(
                    aci: recipient.aci,
                    pni: recipient.pni,
                    e164: E164(recipient.phoneNumber?.stringValue)
                )
            else {
                /// Skip recipients with no identifiers, but don't add to the
                /// list of errors.
                Logger.warn("Skipping empty SignalRecipient!")
                return
            }

            guard !context.localIdentifiers.containsAnyOf(
                aci: contactAddress.aci,
                phoneNumber: contactAddress.e164,
                pni: contactAddress.pni
            ) else {
                // Skip the local user.
                return
            }

            /// Track the `ServiceId`s for this `SignalRecipient`, so we don't
            /// later try and create a duplicate `Contact` frame.
            if let aci = contactAddress.aci {
                archivedServiceIds.insert(aci)
            }
            if let pni = contactAddress.pni {
                archivedServiceIds.insert(pni)
            }
            if let e164 = contactAddress.e164 {
                archivedPhoneNumbers.insert(e164.stringValue)
            }

            var isStoryHidden = false
            if let aci = recipient.aci {
                do {
                    isStoryHidden = try self.storyStore.getOrCreateStoryContextAssociatedData(
                        for: aci,
                        context: context
                    ).isHidden
                } catch let error {
                    errors.append(.archiveFrameError(
                        .unableToReadStoryContextAssociatedData(error),
                        .contact(contactAddress)
                    ))
                }
            }

            let identity: OWSRecipientIdentity?
            do {
                // Read directly from the OWSRecipientIdentity table, bypassing
                // OWSIdentityManager, as we already are working directly
                // with the SignalRecipient and don't need serviceId-based checks.
                identity = try RecipientIdentityRecord
                    .filter(Column(RecipientIdentityRecord.CodingKeys.uniqueId) == recipient.uniqueId)
                    .fetchOne(context.tx.databaseConnection)
                    .map { try OWSRecipientIdentity.fromRecord($0) }
            } catch let error {
                errors.append(.archiveFrameError(
                    .unableToFetchRecipientIdentity(error),
                    .contact(contactAddress)
                ))
                return
            }

            let contact = self.buildContactRecipient(
                aci: contactAddress.aci,
                pni: contactAddress.pni,
                e164: contactAddress.e164,
                username: recipient.aci.flatMap { aci in
                    self.usernameLookupManager.fetchUsername(
                        forAci: aci,
                        transaction: context.tx
                    )
                },
                isBlocked: blockedAddresses.contains(recipient.address),
                isWhitelisted: whitelistedAddresses.contains(recipient.address),
                isStoryHidden: isStoryHidden,
                visibility: { () -> BackupProto_Contact.Visibility in
                    guard let hiddenRecipient = self.recipientHidingManager.fetchHiddenRecipient(
                        signalRecipient: recipient,
                        tx: context.tx
                    ) else {
                        return .visible
                    }

                    if
                        self.recipientHidingManager.isHiddenRecipientThreadInMessageRequest(
                            hiddenRecipient: hiddenRecipient,
                            contactThread: self.threadStore.fetchContactThread(
                                recipient: recipient,
                                context: context
                            ),
                            tx: context.tx
                        )
                    {
                        return .hiddenMessageRequest
                    } else {
                        return .hidden
                    }
                }(),
                registration: { () -> BackupProto_Contact.OneOf_Registration in
                    if !recipient.isRegistered {
                        var notRegistered = BackupProto_Contact.NotRegistered()
                        notRegistered.unregisteredTimestamp = recipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp

                        return .notRegistered(notRegistered)
                    }

                    return .registered(BackupProto_Contact.Registered())
                }(),
                userProfile: self.profileManager.getUserProfile(
                    for: recipient.address,
                    tx: context.tx
                ),
                identity: identity
            )

            writeToStream(contact: contact, contactAddress: contactAddress)
        }

        do {
            try recipientStore.enumerateAllSignalRecipients(context, block: { recipient in
                autoreleasepool { recipientBlock(recipient) }
            })
        } catch let error as CancellationError {
            throw error
        } catch {
            return .completeFailure(.fatalArchiveError(.recipientIteratorError(error)))
        }

        /// After enumerating all `SignalRecipient`s, we enumerate
        /// `OWSUserProfile`s. It's possible that we'll have an `OWSUserProfile`
        /// for a user for whom we have no `SignalRecipient`; for example, a
        /// member of a group we're in whose profile we've fetched, but with
        /// whom we've never messaged.
        ///
        /// It's important that the profile info we have for those users is
        /// included in the Backup. However, if we had a `SignalRecipient` for
        /// the profile (both tables store an ACI), the profile info was already
        /// archived and we should not make another `Contact` frame for the same
        /// ACI.
        ///
        /// A known side-effect of archiving `Contact` frames for
        /// `OWSUserProfile`s is that when we restore these frames we'll create
        /// both an `OWSUserProfile` and a `SignalRecipient` for this entry.
        /// That's fine, even good: ideally we want to move towards a 1:1
        /// relationship between `SignalRecipient` and other user-related models
        /// like `OWSUserProfile`. If, in the future, we have an enforced 1:1
        /// relationship between `SignalRecipient` and `OWSUserProfile`, we can
        /// remove this code.
        profileManager.enumerateUserProfiles(tx: context.tx) { userProfile in
            autoreleasepool {
                if let serviceId = userProfile.serviceId {
                    let (inserted, _) = archivedServiceIds.insert(serviceId)

                    if !inserted {
                        /// Bail early if we've already archived a `Contact` for this
                        /// service ID.
                        return
                    }
                }
                if let phoneNumber = userProfile.phoneNumber {
                    let (inserted, _) = archivedPhoneNumbers.insert(phoneNumber)

                    if !inserted {
                        /// Bail early if we've already archived a `Contact` for this
                        /// phone number.
                        return
                    }
                }

                guard
                    let contactAddress = MessageBackup.ContactAddress(
                        aci: userProfile.serviceId as? Aci,
                        pni: userProfile.serviceId as? Pni,
                        e164: userProfile.phoneNumber.flatMap { E164($0) }
                    )
                else {
                    /// Skip profiles with no identifiers, but don't add to the
                    /// list of errors.
                    Logger.warn("Skipping empty OWSUserProfile!")
                    return
                }

                let signalServiceAddress: MessageBackup.InteropAddress
                switch userProfile.internalAddress {
                case .localUser:
                    /// Skip the local user. We need to check `internalAddress`
                    /// here, since the "local user profile" has historically been
                    /// persisted with a special, magic phone number.
                    return
                case .otherUser(let _signalServiceAddress):
                    signalServiceAddress = _signalServiceAddress
                }

                let contact = buildContactRecipient(
                    aci: contactAddress.aci,
                    pni: contactAddress.pni,
                    e164: contactAddress.e164,
                    username: nil, // If we have a user profile, we have no username.
                    isBlocked: blockedAddresses.contains(signalServiceAddress),
                    isWhitelisted: whitelistedAddresses.contains(signalServiceAddress),
                    isStoryHidden: false, // Can't have a story if there's no recipient.
                    visibility: .visible, // Can't have hidden if there's no recipient.
                    registration: {
                        // We don't know if they're registered; if we did, we'd have
                        // a recipient.
                        var notRegistered = BackupProto_Contact.NotRegistered()
                        notRegistered.unregisteredTimestamp = 0

                        return .notRegistered(notRegistered)
                    }(),
                    userProfile: userProfile,
                    // We don't have (and can't fetch) identity info for
                    // profile addresses without SignalRecipients.
                    identity: nil
                )

                writeToStream(
                    contact: contact,
                    contactAddress: contactAddress
                )
            }
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    /// It is possible to have a TSContactThread for which we have no SignalRecipient
    /// or OWSUserProfile. One way to create this is to tap "Call with Signal" from the system
    /// contacts app, for a number that is not registered on Signal.
    /// If this happens, when we archive the TSContactThread we need to also archive
    /// a Contact recipient that we create on-the-fly. This is only used if we were unable
    /// to find a Recipient for the thread's address; in other words there was not a
    /// corresponding recipient that we archived earlier.
    func archiveContactRecipientForOrphanedContactThread(
        _ contactThread: TSContactThread,
        address: MessageBackup.ContactAddress,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> MessageBackup.ArchiveSingleFrameResult<RecipientId, MessageBackup.ThreadUniqueId> {
        let existingRecipient = recipientStore.fetchRecipient(
            for: address,
            context: context.recipientContext
        )
        // If we have an existing recipient, this is an error. It means we
        // _should_ have found the recipient on the context, but did not.
        guard existingRecipient == nil else {
            return .failure(.archiveFrameError(
                .referencedRecipientIdMissing(address.asArchivingAddress()),
                .init(thread: contactThread)
            ))
        }

        // We don't know if they're registered; if we did there
        // would be a SignalRecipient.
        var registration = BackupProto_Contact.NotRegistered()
        registration.unregisteredTimestamp = 0

        let contactProto = buildContactRecipient(
            aci: address.aci,
            pni: address.pni,
            e164: address.e164,
            username: nil,
            isBlocked: blockingManager.blockedAddresses(tx: context.tx)
                .contains(address.asInteropAddress()),
            isWhitelisted: profileManager.allWhitelistedAddresses(tx: context.tx)
                .contains(address.asInteropAddress()),
            // If there's no recipient, neither can be hidden
            isStoryHidden: false,
            visibility: .visible,
            registration: .notRegistered(registration),
            userProfile: nil,
            identity: nil
        )

        let recipientAddress = address.asArchivingAddress()
        let recipientId = context.recipientContext.assignRecipientId(to: recipientAddress)

        let maybeError: MessageBackup.ArchiveFrameError<MessageBackup.ThreadUniqueId>?
        maybeError = Self.writeFrameToStream(
            stream,
            objectId: .init(thread: contactThread),
            frameBuilder: {
                var recipient = BackupProto_Recipient()
                recipient.id = recipientId.value
                recipient.destination = .contact(contactProto)

                var frame = BackupProto_Frame()
                frame.item = .recipient(recipient)
                return frame
            }
        )

        if let maybeError {
            return .failure(maybeError)
        }
        return .success(recipientId)
    }

    private func buildContactRecipient(
        aci: Aci?,
        pni: Pni?,
        e164: E164?,
        username: String?,
        isBlocked: Bool,
        isWhitelisted: Bool,
        isStoryHidden: Bool,
        visibility: BackupProto_Contact.Visibility,
        registration: BackupProto_Contact.OneOf_Registration,
        userProfile: OWSUserProfile?,
        identity: OWSRecipientIdentity?
    ) -> BackupProto_Contact {
        var contact = BackupProto_Contact()
        contact.blocked = isBlocked
        contact.profileSharing = isWhitelisted
        contact.hideStory = isStoryHidden
        contact.visibility = visibility
        contact.registration = registration
        if let identity, let identityKey = try? identity.identityKeyObject {
            // `serialize()`, which includes the keyType prefix.
            contact.identityKey = Data(identityKey.publicKey.serialize())
            switch identity.verificationState {
            case .default, .defaultAcknowledged:
                contact.identityState = .default
            case .verified:
                contact.identityState = .verified
            case .noLongerVerified:
                contact.identityState = .unverified
            }
        }

        if let aci {
            contact.aci = aci.rawUUID.data
        }
        if let pni {
            contact.pni = pni.rawUUID.data
        }
        if let e164UInt = e164?.uint64Value {
            contact.e164 = e164UInt
        }
        if let username {
            contact.username = username
        }

        if let profileKey = userProfile?.profileKey {
            contact.profileKey = profileKey.keyData
        }
        if let givenName = userProfile?.givenName?.nilIfEmpty {
            contact.profileGivenName = givenName
        }
        if let familyName = userProfile?.familyName?.nilIfEmpty {
            contact.profileFamilyName = familyName
        }

        return contact
    }

    // MARK: -

    func restoreContactRecipientProto(
        _ contactProto: BackupProto_Contact,
        recipient: BackupProto_Recipient,
        context: MessageBackup.RecipientRestoringContext
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

        let recipientProto = recipient
        let recipient: SignalRecipient = .fromBackup(
            backupContactAddress,
            isRegistered: isRegistered,
            unregisteredAtTimestamp: unregisteredTimestamp
        )
        do {
            try recipientStore.insertRecipient(recipient, context: context)
        } catch {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipientProto.recipientId)])
        }

        /// No Backup code should be relying on the SSA cache, but once we've
        /// finished restoring and launched we want the cache to have accurate
        /// mappings based on the recipients we just restored.
        signalServiceAddressCache.updateRecipient(recipient, tx: context.tx)

        if
            let aci = recipient.aci,
            contactProto.hasUsername
        {
            usernameLookupManager.saveUsername(contactProto.username, forAci: aci, transaction: context.tx)
        }

        if contactProto.hasIdentityKey {
            let identityKey: Data
            do {
                identityKey = try IdentityKey(publicKey: PublicKey(contactProto.identityKey))
                    // 'keyBytes', which drops the keyType prefix
                    .publicKey.keyBytes.asData
            } catch {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidContactIdentityKey), recipientProto.recipientId)])
            }

            let verificationState: OWSVerificationState
            switch contactProto.identityState {
            case .default:
                verificationState = .default
            case .verified:
                verificationState = .verified
            case .unverified:
                verificationState = .noLongerVerified
            case .UNRECOGNIZED:
                return .failure([.restoreFrameError(
                    .invalidProtoData(.unknownContactIdentityState),
                    recipientProto.recipientId
                )])
            }

            // Write directly to the OWSRecipientIdentity table, bypassing
            // OWSIdentityManager, as we already are working directly
            // with the SignalRecipient and don't need serviceId-based checks.
            let identity = OWSRecipientIdentity(
                recipientUniqueId: recipient.uniqueId,
                identityKey: identityKey,
                isFirstKnownKey: true,
                createdAt: dateProvider(),
                verificationState: verificationState
            )
            do {
                try identity.asRecord().insert(context.tx.databaseConnection)
            } catch {
                return .failure([.restoreFrameError(
                    .databaseInsertionFailed(error),
                    recipientProto.recipientId
                )])
            }
        }

        if contactProto.profileSharing {
            // Add to the whitelist.
            profileManager.addToWhitelist(recipient.address, tx: context.tx)
        }

        if contactProto.blocked {
            blockingManager.addBlockedAddress(recipient.address, tx: context.tx)
        }

        do {
            func addHiddenRecipient(isHiddenInKnownMessageRequestState: Bool) throws {
                try recipientHidingManager.addHiddenRecipient(
                    recipient,
                    inKnownMessageRequestState: isHiddenInKnownMessageRequestState,
                    wasLocallyInitiated: false,
                    tx: context.tx
                )

                context.setNeedsPostRestoreContactHiddenInfoMessage(
                    recipientId: recipientProto.recipientId
                )
            }

            switch contactProto.visibility {
            case .hidden:
                try addHiddenRecipient(isHiddenInKnownMessageRequestState: false)
            case .hiddenMessageRequest:
                try addHiddenRecipient(isHiddenInKnownMessageRequestState: true)
            case .visible, .UNRECOGNIZED:
                break
            }
        } catch let error {
            return restoreFrameError(.databaseInsertionFailed(error))
        }

        var partialErrors = [MessageBackup.RestoreFrameError<RecipientId>]()

        // We only need to active hide, since unhidden is the default.
        if contactProto.hideStory, let aci = backupContactAddress.aci {
            do {
                try storyStore.createStoryContextAssociatedData(
                    for: aci,
                    isHidden: true,
                    context: context
                )
            } catch let error {
                // Don't fail entirely; the story will just be unhidden.
                partialErrors.append(.restoreFrameError(.databaseInsertionFailed(error), recipientProto.recipientId))
            }
        }

        profileManager.upsertOtherUserProfile(
            insertableAddress: profileInsertableAddress,
            givenName: contactProto.profileGivenName.nilIfEmpty,
            familyName: contactProto.profileFamilyName.nilIfEmpty,
            profileKey: profileKey,
            tx: context.tx
        )

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}
