//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// TODO: Should we use these caches in NSE?
fileprivate extension OWSContactsManager {
    static let skipContactAvatarBlurByUuidStore = SDSKeyValueStore(collection: "OWSContactsManager.skipContactAvatarBlurByUuidStore")
    static let skipGroupAvatarBlurByGroupIdStore = SDSKeyValueStore(collection: "OWSContactsManager.skipGroupAvatarBlurByGroupIdStore")

    // MARK: - Low Trust

    enum LowTrustType {
        case avatarBlurring
        case unknownThreadWarning

        var allowUserToDismiss: Bool {
            self == .avatarBlurring
        }

        var checkForTrustedGroupMembers: Bool {
            self == .unknownThreadWarning
        }

        var cache: LowTrustCache {
            switch self {
            case .avatarBlurring:
                return OWSContactsManager.avatarBlurringCache
            case .unknownThreadWarning:
                return OWSContactsManager.unknownThreadWarningCache
            }
        }
    }

    struct LowTrustCache {
        let contactCache = AtomicSet<UUID>()
        let groupCache = AtomicSet<Data>()

        func contains(groupThread: TSGroupThread) -> Bool {
            groupCache.contains(groupThread.groupId)
        }

        func contains(contactThread: TSContactThread) -> Bool {
            contains(address: contactThread.contactAddress)
        }

        func contains(address: SignalServiceAddress) -> Bool {
            guard let uuid = address.uuid else {
                return false
            }
            return contactCache.contains(uuid)
        }

        func add(groupThread: TSGroupThread) {
            groupCache.insert(groupThread.groupId)
        }

        func add(contactThread: TSContactThread) {
            add(address: contactThread.contactAddress)
        }

        func add(address: SignalServiceAddress) {
            guard let uuid = address.uuid else {
                return
            }
            contactCache.insert(uuid)
        }
    }

    static let unknownThreadWarningCache = LowTrustCache()
    static let avatarBlurringCache = LowTrustCache()

    private func isLowTrustThread(_ thread: TSThread,
                                  lowTrustType: LowTrustType,
                                  transaction: SDSAnyReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isLowTrustContact(contactThread: contactThread,
                                     lowTrustType: lowTrustType,
                                     transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return isLowTrustGroup(groupThread: groupThread,
                                   lowTrustType: lowTrustType,
                                   transaction: transaction)
        } else {
            owsFailDebug("Invalid thread.")
            return false
        }
    }

    private func isLowTrustContact(address: SignalServiceAddress,
                                   lowTrustType: LowTrustType,
                                   transaction: SDSAnyReadTransaction) -> Bool {
        let cache = lowTrustType.cache
        if cache.contains(address: address) {
            return false
        }
        guard let contactThread = TSContactThread.getWithContactAddress(address,
                                                                        transaction: transaction) else {
            cache.add(address: address)
            return false
        }
        return isLowTrustContact(contactThread: contactThread,
                                 lowTrustType: lowTrustType,
                                 transaction: transaction)
    }

    private func isLowTrustContact(contactThread: TSContactThread,
                                   lowTrustType: LowTrustType,
                                   transaction: SDSAnyReadTransaction) -> Bool {
        let cache = lowTrustType.cache
        let address = contactThread.contactAddress
        if cache.contains(address: address) {
            return false
        }
        if !contactThread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) {
            cache.add(address: address)
            return false
        }
        // ...and not in a whitelisted group with the locar user.
        if isInWhitelistedGroupWithLocalUser(address: address,
                                             transaction: transaction) {
            cache.add(address: address)
            return false
        }
        // We can skip avatar blurring if the user has explicitly waived the blurring.
        if lowTrustType.allowUserToDismiss,
           let uuid = address.uuid,
           Self.skipContactAvatarBlurByUuidStore.getBool(uuid.uuidString,
                                                         defaultValue: false,
                                                         transaction: transaction) {
            cache.add(address: address)
            return false
        }
        return true
    }

    private func isLowTrustGroup(groupThread: TSGroupThread,
                                 lowTrustType: LowTrustType,
                                 transaction: SDSAnyReadTransaction) -> Bool {
        let cache = lowTrustType.cache
        let groupId = groupThread.groupId
        if cache.contains(groupThread: groupThread) {
            return false
        }
        if nil == groupThread.groupModel.avatarHash {
            // DO NOT add to the cache.
            return false
        }
        if !groupThread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) {
            cache.add(groupThread: groupThread)
            return false
        }
        // We can skip avatar blurring if the user has explicitly waived the blurring.
        if lowTrustType.allowUserToDismiss,
           Self.skipGroupAvatarBlurByGroupIdStore.getBool(groupId.hexadecimalString,
                                                          defaultValue: false,
                                                          transaction: transaction) {
            cache.add(groupThread: groupThread)
            return false
        }
        // We can skip "unknown thread warnings" if a group has members which are trusted.
        if lowTrustType.checkForTrustedGroupMembers,
           hasWhitelistedGroupMember(groupThread: groupThread, transaction: transaction) {
            cache.add(groupThread: groupThread)
            return false
        }
        return true
    }

    // MARK: -

    private static let isInWhitelistedGroupWithLocalUserCache = AtomicDictionary<UUID, Bool>()

    private func isInWhitelistedGroupWithLocalUser(address otherAddress: SignalServiceAddress,
                                                   transaction: SDSAnyReadTransaction) -> Bool {
        let cache = Self.isInWhitelistedGroupWithLocalUserCache
        if let cacheKey = otherAddress.uuid,
           let cachedValue = cache[cacheKey] {
            return cachedValue
        }
        let result: Bool = {
            guard let localAddress = tsAccountManager.localAddress else {
                owsFailDebug("Missing localAddress.")
                return false
            }
            let otherGroupThreadIds = TSGroupThread.groupThreadIds(with: otherAddress, transaction: transaction)
            guard !otherGroupThreadIds.isEmpty else {
                return false
            }
            let localGroupThreadIds = TSGroupThread.groupThreadIds(with: localAddress, transaction: transaction)
            let groupThreadIds = Set(otherGroupThreadIds).intersection(localGroupThreadIds)
            for groupThreadId in groupThreadIds {
                guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId,
                                                                          transaction: transaction) else {
                    owsFailDebug("Missing group thread")
                    continue
                }
                if profileManager.isGroupId(inProfileWhitelist: groupThread.groupId,
                                            transaction: transaction) {
                    return true
                }
            }
            return false
        }()
        if let cacheKey = otherAddress.uuid {
            cache[cacheKey] = result
        }
        return result
    }

    private static let hasWhitelistedGroupMemberCache = AtomicDictionary<Data, Bool>()

    private func hasWhitelistedGroupMember(groupThread: TSGroupThread,
                                           transaction: SDSAnyReadTransaction) -> Bool {
        let cache = Self.hasWhitelistedGroupMemberCache
        let cacheKey = groupThread.groupId
        if let cachedValue = cache[cacheKey] {
            return cachedValue
        }
        let result: Bool = {
            for groupMember in groupThread.groupMembership.fullMembers {
                if profileManager.isUser(inProfileWhitelist: groupMember, transaction: transaction) {
                    return true
                }
            }
            return false
        }()
        cache[cacheKey] = result
        return result
    }
}

// MARK: -

@objc
public extension OWSContactsManager {

    // MARK: - Low Trust Thread Warnings

    func shouldShowUnknownThreadWarning(thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustThread(thread,
                         lowTrustType: .unknownThreadWarning,
                         transaction: transaction)
    }

    // MARK: - Avatar Blurring

    func shouldBlurAvatar(thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustThread(thread,
                         lowTrustType: .avatarBlurring,
                         transaction: transaction)
    }

    func shouldBlurContactAvatar(address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustContact(address: address,
                          lowTrustType: .avatarBlurring,
                          transaction: transaction)
    }

    func shouldBlurContactAvatar(contactThread: TSContactThread,
                                 transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustContact(contactThread: contactThread,
                          lowTrustType: .avatarBlurring,
                          transaction: transaction)
    }

    func shouldBlurGroupAvatar(groupThread: TSGroupThread,
                               transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustGroup(groupThread: groupThread,
                        lowTrustType: .avatarBlurring,
                        transaction: transaction)
    }

    static let skipContactAvatarBlurDidChange = NSNotification.Name("skipContactAvatarBlurDidChange")
    static let skipContactAvatarBlurAddressKey = "skipContactAvatarBlurAddressKey"
    static let skipGroupAvatarBlurDidChange = NSNotification.Name("skipGroupAvatarBlurDidChange")
    static let skipGroupAvatarBlurGroupUniqueIdKey = "skipGroupAvatarBlurGroupUniqueIdKey"

    func doNotBlurContactAvatar(address: SignalServiceAddress,
                                transaction: SDSAnyWriteTransaction) {

        guard let uuid = address.uuid else {
            owsFailDebug("Missing uuid for user.")
            return
        }
        guard !Self.skipContactAvatarBlurByUuidStore.getBool(uuid.uuidString,
                                                             defaultValue: false,
                                                             transaction: transaction) else {
            owsFailDebug("Value did not change.")
            return
        }
        Self.skipContactAvatarBlurByUuidStore.setBool(true,
                                                      key: uuid.uuidString,
                                                      transaction: transaction)
        if let contactThread = TSContactThread.getWithContactAddress(address,
                                                                     transaction: transaction) {
            databaseStorage.touch(thread: contactThread, shouldReindex: false, transaction: transaction)
        }
        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(Self.skipContactAvatarBlurDidChange,
                                                                 object: nil,
                                                                 userInfo: [
                                                                    Self.skipContactAvatarBlurAddressKey: address
                                                                 ])
        }
    }

    func doNotBlurGroupAvatar(groupThread: TSGroupThread,
                              transaction: SDSAnyWriteTransaction) {

        let groupId = groupThread.groupId
        let groupUniqueId = groupThread.uniqueId
        guard !Self.skipGroupAvatarBlurByGroupIdStore.getBool(groupId.hexadecimalString,
                                                              defaultValue: false,
                                                              transaction: transaction) else {
            owsFailDebug("Value did not change.")
            return
        }
        Self.skipGroupAvatarBlurByGroupIdStore.setBool(true,
                                                       key: groupId.hexadecimalString,
                                                       transaction: transaction)
        databaseStorage.touch(thread: groupThread, shouldReindex: false, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(Self.skipGroupAvatarBlurDidChange,
                                                                 object: nil,
                                                                 userInfo: [
                                                                    Self.skipGroupAvatarBlurGroupUniqueIdKey: groupUniqueId
                                                                 ])
        }
    }

    @nonobjc
    func blurAvatar(_ image: UIImage) -> UIImage? {
        do {
            return try image.withGaussianBlur(radius: 16, resizeToMaxPixelDimension: 100)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Sorting

    func sortSignalAccountsWithSneakyTransaction(_ signalAccounts: [SignalAccount]) -> [SignalAccount] {
        databaseStorage.read { transaction in
            self.sortSignalAccounts(signalAccounts, transaction: transaction)
        }
    }

    func sortSignalAccounts(_ signalAccounts: [SignalAccount],
                            transaction: SDSAnyReadTransaction) -> [SignalAccount] {

        typealias SortableAccount = SortableValue<SignalAccount>
        let sortableAccounts = signalAccounts.map { signalAccount in
            return SortableAccount(value: signalAccount,
                                   comparableName: self.comparableName(for: signalAccount,
                                                                          transaction: transaction),
                                   comparableAddress: signalAccount.recipientAddress.stringForDisplay)
        }
        return sort(sortableAccounts)
    }

    // MARK: -

    func sortSignalServiceAddressesWithSneakyTransaction(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            self.sortSignalServiceAddresses(addresses, transaction: transaction)
        }
    }

    func sortSignalServiceAddresses(_ addresses: [SignalServiceAddress],
                                    transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {

        typealias SortableAddress = SortableValue<SignalServiceAddress>
        let sortableAddresses = addresses.map { address in
            return SortableAddress(value: address,
                                   comparableName: self.comparableName(for: address,
                                                                          transaction: transaction),
                                   comparableAddress: address.stringForDisplay)
        }
        return sort(sortableAddresses)
    }

    // MARK: -

    func shortestDisplayName(
        forGroupMember groupMember: SignalServiceAddress,
        inGroup groupModel: TSGroupModel,
        transaction: SDSAnyReadTransaction
    ) -> String {

        let fullName = displayName(for: groupMember, transaction: transaction)
        let shortName = shortDisplayName(for: groupMember, transaction: transaction)
        guard shortName != fullName else { return fullName }

        // Try to return just the short name unless the group contains another
        // member with the same short name.

        for otherMember in groupModel.groupMembership.fullMembers {
            guard otherMember != groupMember else { continue }

            // Use the full name if the member's short name matches
            // another member's full or short name.
            let otherFullName = displayName(for: otherMember, transaction: transaction)
            guard otherFullName != shortName else { return fullName }

            let otherShortName = shortDisplayName(for: otherMember, transaction: transaction)
            guard otherShortName != shortName else { return fullName }
        }

        return shortName
    }
}

// MARK: -

private struct SortableValue<T> {
    let value: T
    let comparableName: String
    let comparableAddress: String

    init (value: T, comparableName: String, comparableAddress: String) {
        self.value = value
        self.comparableName = comparableName.lowercased()
        self.comparableAddress = comparableAddress.lowercased()
    }
}

// MARK: -

extension SortableValue: Equatable, Comparable {

    // MARK: - Equatable

    public static func == (lhs: SortableValue<T>, rhs: SortableValue<T>) -> Bool {
        return (lhs.comparableName == rhs.comparableName &&
                lhs.comparableAddress == rhs.comparableAddress)
    }

    // MARK: - Comparable

    public static func < (left: SortableValue<T>, right: SortableValue<T>) -> Bool {
        // We want to sort E164 phone numbers _after_ names.
        let leftHasE164Prefix = left.comparableName.hasPrefix("+")
        let rightHasE164Prefix = right.comparableName.hasPrefix("+")

        if leftHasE164Prefix && !rightHasE164Prefix {
            return false
        } else if !leftHasE164Prefix && rightHasE164Prefix {
            return true
        }

        if left.comparableName != right.comparableName {
            return left.comparableName < right.comparableName
        } else {
            return left.comparableAddress < right.comparableAddress
        }
    }
}

// MARK: -

fileprivate extension OWSContactsManager {
    func sort<T>(_ values: [SortableValue<T>]) -> [T] {
        return values.sorted().map { $0.value }
    }
}

// MARK: -

extension OWSContactsManager {

    @objc
    public func avatarImage(forAddress address: SignalServiceAddress?,
                            shouldValidate: Bool,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        guard let imageData = avatarImageData(forAddress: address,
                                              shouldValidate: shouldValidate,
                                              transaction: transaction) else {
            return nil
        }
        guard let image = UIImage(data: imageData) else {
            owsFailDebug("Invalid image.")
            return nil
        }
        return image
    }

    @objc
    public func avatarImageData(forAddress address: SignalServiceAddress?,
                                shouldValidate: Bool,
                                transaction: SDSAnyReadTransaction) -> Data? {
        guard let address = address,
              address.isValid else {
                  owsFailDebug("Missing or invalid address.")
                  return nil
              }

        if SSKPreferences.preferContactAvatars(transaction: transaction) {
            return (systemContactOrSyncedImageData(forAddress: address,
                                                   shouldValidate: shouldValidate,
                                                   transaction: transaction)
                    ?? profileAvatarImageData(forAddress: address,
                                              shouldValidate: shouldValidate,
                                              transaction: transaction))
        } else {
            return (profileAvatarImageData(forAddress: address,
                                           shouldValidate: shouldValidate,
                                           transaction: transaction)
                    ?? systemContactOrSyncedImageData(forAddress: address,
                                                      shouldValidate: shouldValidate,
                                                      transaction: transaction))
        }
    }

    fileprivate func profileAvatarImageData(forAddress address: SignalServiceAddress?,
                                            shouldValidate: Bool,
                                            transaction: SDSAnyReadTransaction) -> Data? {
        func validateIfNecessary(_ imageData: Data) -> Data? {
            guard shouldValidate else {
                return imageData
            }
            guard imageData.ows_isValidImage else {
                owsFailDebug("Invalid image data.")
                return nil
            }
            return imageData
        }

        guard let address = address,
              address.isValid else {
                  owsFailDebug("Missing or invalid address.")
                  return nil
              }

        if let avatarData = profileManagerImpl.profileAvatarData(for: address, transaction: transaction),
           let validData = validateIfNecessary(avatarData) {
            return validData
        }

        return nil
    }

    fileprivate func systemContactOrSyncedImageData(forAddress address: SignalServiceAddress?,
                                                    shouldValidate: Bool,
                                                    transaction: SDSAnyReadTransaction) -> Data? {
        func validateIfNecessary(_ imageData: Data) -> Data? {
            guard shouldValidate else {
                return imageData
            }
            guard imageData.ows_isValidImage else {
                owsFailDebug("Invalid image data.")
                return nil
            }
            return imageData
        }

        guard let address = address,
              address.isValid else {
                  owsFailDebug("Missing or invalid address.")
                  return nil
              }

        guard !address.isLocalAddress else {
            // Never use system contact or synced image data for the local user
            return nil
        }

        if let phoneNumber = self.phoneNumber(for: address, transaction: transaction),
           let contact = contactsManagerCache.contact(forPhoneNumber: phoneNumber, transaction: transaction),
           let cnContactId = contact.cnContactId,
           let avatarData = self.avatarData(forCNContactId: cnContactId),
           let validData = validateIfNecessary(avatarData) {
            return validData
        }

        // If we haven't loaded system contacts yet, we may have a cached copy in the db
        if let signalAccount = self.fetchSignalAccount(for: address, transaction: transaction) {
            if let contact = signalAccount.contact,
               let cnContactId = contact.cnContactId,
               let avatarData = self.avatarData(forCNContactId: cnContactId),
               let validData = validateIfNecessary(avatarData) {
                return validData
            }

            if let contactAvatarData = signalAccount.buildContactAvatarJpegData() {
                return contactAvatarData
            }
        }
        return nil
    }
}

// MARK: - Internals

extension OWSContactsManager {
    // TODO: It would be preferable to figure out some way to use ReverseDispatchQueue.
    @objc
    static let intersectionQueue = DispatchQueue(label: OWSDispatch.createLabel("contacts.intersectionQueue"))
    @objc
    var intersectionQueue: DispatchQueue { Self.intersectionQueue }

    // TODO: Move to Contact class?
    private static func accountLabel(forFetchedContact fetchedContact: FetchedContact,
                                     address: SignalServiceAddress) -> String? {

        owsAssertDebug(address.isValid)
        let registeredAddresses = fetchedContact.registeredAddresses
        owsAssertDebug(registeredAddresses.contains(address))
        let contact = fetchedContact.contact

        guard registeredAddresses.count > 1 else {
            return nil
        }

        // 1. Find the address type of this account.
        let addressLabel: String = contact.name(for: address,
                                                   registeredAddresses: registeredAddresses).filterStringForDisplay()

        // 2. Find all addresses for this contact of the same type.
        let addressesWithTheSameName = registeredAddresses.filter {
            addressLabel == contact.name(for: $0,
                                            registeredAddresses: registeredAddresses).filterStringForDisplay()
        }.stableSort()

        owsAssertDebug(addressesWithTheSameName.contains(address))
        if addressesWithTheSameName.count > 1,
           let index = addressesWithTheSameName.firstIndex(of: address) {
            let format = OWSLocalizedString("PHONE_NUMBER_TYPE_AND_INDEX_NAME_FORMAT",
                                           comment: "Format for phone number label with an index. Embeds {{Phone number label (e.g. 'home')}} and {{index, e.g. 2}}.")
            return String(format: format,
                          addressLabel,
                          OWSFormat.formatUInt(UInt(index))).filterStringForDisplay()
        } else {
            return addressLabel
        }
    }

    private static func buildContactAvatarHash(contact: Contact) -> Data? {
        func buildHash() -> Data? {
            guard let cnContactId: String = contact.cnContactId else {
                owsFailDebug("Missing cnContactId.")
                return nil
            }
            guard let contactAvatarData = Self.contactsManager.avatarData(forCNContactId: cnContactId) else {
                return nil
            }
            guard let contactAvatarHash = Cryptography.computeSHA256Digest(contactAvatarData) else {
                owsFailDebug("Could not digest contactAvatarData.")
                return nil
            }
            return contactAvatarHash
        }
        if CurrentAppContext().isMainApp {
            return buildHash()
        } else {
            return autoreleasepool {
                buildHash()
            }
        }
    }

    private struct SystemContactsManagerCache {
        let signalAccounts: [SignalAccount]
        let seenAddresses: Set<SignalServiceAddress>
    }

    private struct FetchedContact {
        let contact: Contact
        let signalRecipients: [SignalRecipient]
        let registeredAddresses: [SignalServiceAddress]
    }

    private static func buildSystemContactsManagerCache(forLocalSystemContacts contacts: [Contact],
                                                        transaction: SDSAnyReadTransaction) -> SystemContactsManagerCache {

        let fetchedContacts: [FetchedContact] = contacts.map { contact in
            let signalRecipients = contact.signalRecipients(transaction: transaction)
            let registeredAddresses = contact.registeredAddresses(transaction: transaction)
            return FetchedContact(contact: contact,
                                  signalRecipients: signalRecipients,
                                  registeredAddresses: registeredAddresses)
        }
        var seenAddresses = Set<SignalServiceAddress>()
        var signalAccounts = [SignalAccount]()
        for fetchedContact in fetchedContacts {
            let contact = fetchedContact.contact

            var signalRecipients = fetchedContact.signalRecipients
            guard !signalRecipients.isEmpty else {
                continue
            }
            // TODO: Confirm ordering.
            signalRecipients.sort { $0.compare($1) == .orderedAscending }
            // We use Batching since contact avatars could be large.
            Batching.enumerate(signalRecipients, batchSize: 12) { signalRecipient in
                if seenAddresses.contains(signalRecipient.address) {
                    Logger.verbose("Ignoring duplicate contact: \(signalRecipient.address), \(contact.fullName)")
                    return
                }
                seenAddresses.insert(signalRecipient.address)

                var multipleAccountLabelText: String?
                if signalRecipients.count > 1 {
                    multipleAccountLabelText = Self.accountLabel(forFetchedContact: fetchedContact,
                                                                 address: signalRecipient.address)
                }
                let contactAvatarHash = Self.buildContactAvatarHash(contact: contact)
                let signalAccount = SignalAccount(signalRecipient: signalRecipient,
                                                  contact: contact,
                                                  contactAvatarHash: contactAvatarHash,
                                                  multipleAccountLabelText: multipleAccountLabelText)
                signalAccounts.append(signalAccount)
            }
        }
        return SystemContactsManagerCache(signalAccounts: signalAccounts.stableSort(),
                                          seenAddresses: seenAddresses)
    }

    @objc
    func buildSignalAccountsAndUpdatePersistedState(
        forFetchedSystemContacts localSystemContacts: [Contact]
    ) {
        intersectionQueue.async {
            var localSystemContactsSignalAccounts = [SignalAccount]()
            var seenAddresses = Set<SignalServiceAddress>()
            var persistedSignalAccounts = [SignalAccount]()
            var persistedSignalAccountMap = [SignalServiceAddress: SignalAccount]()
            var signalAccountsToKeep = [SignalServiceAddress: SignalAccount]()
            Self.databaseStorage.read { transaction in
                let systemContactsManagerCache = Self.buildSystemContactsManagerCache(
                    forLocalSystemContacts: localSystemContacts,
                    transaction: transaction
                )
                localSystemContactsSignalAccounts = systemContactsManagerCache.signalAccounts
                seenAddresses = systemContactsManagerCache.seenAddresses

                SignalAccount.anyEnumerate(transaction: transaction) { (signalAccount, _) in
                    persistedSignalAccountMap[signalAccount.recipientAddress] = signalAccount
                    persistedSignalAccounts.append(signalAccount)

                    // If we find a persisted contact that is not from the
                    // local address book, it represents a contact from the
                    // address book on the primary device that was synced to
                    // this (linked) device. We should keep it, and not
                    // overwrite it since the primary device's system contacts
                    // always take precendence.
                    if
                        let contact = signalAccount.contact,
                        !contact.isFromLocalAddressBook
                    {
                        signalAccountsToKeep[signalAccount.recipientAddress] = signalAccount
                    }
                }
            }

            var signalAccountsToUpsert = [SignalAccount]()
            for signalAccount in localSystemContactsSignalAccounts {
                // The user might have multiple entries in their address book with the same phone number.
                if
                    let otherSignalAccount = signalAccountsToKeep[signalAccount.recipientAddress],
                    let contact = otherSignalAccount.contact,
                    contact.isFromLocalAddressBook
                {
                    Logger.warn("Ignoring redundant signal account: \(signalAccount.recipientAddress)")
                    continue
                }

                if let persistedSignalAccount = persistedSignalAccountMap[signalAccount.recipientAddress] {
                    let keepPersistedAccount: Bool

                    if persistedSignalAccount.hasSameContent(signalAccount) {
                        // Same content, no need to update.
                        keepPersistedAccount = true
                    } else if
                        let contact = persistedSignalAccount.contact,
                        !contact.isFromLocalAddressBook
                    {
                        // If the contact is not local to this device, then we are
                        // a linked device and have synced this from the primary.
                        // We should not overwrite the synced primary-device system
                        // contact.
                        keepPersistedAccount = true
                    } else {
                        keepPersistedAccount = false
                    }

                    if keepPersistedAccount {
                        signalAccountsToKeep[signalAccount.recipientAddress] = persistedSignalAccount
                        continue
                    }
                }

                signalAccountsToKeep[signalAccount.recipientAddress] = signalAccount
                signalAccountsToUpsert.append(signalAccount)
            }

            // Clean up orphans.
            var signalAccountsToRemove = [SignalAccount]()
            for signalAccount in persistedSignalAccounts {
                if let signalAccountToKeep = signalAccountsToKeep[signalAccount.recipientAddress],
                   signalAccountToKeep.uniqueId == signalAccount.uniqueId {
                    // If the SignalAccount is going to be inserted or updated,
                    // it doesn't need to be cleaned up.
                    continue
                }
                // Clean up instances that have been replaced by another instance
                // or are no longer in the system contacts.
                signalAccountsToRemove.append(signalAccount)
            }

            // Update cached SignalAccounts on disk
            Self.databaseStorage.write { transaction in
                if !signalAccountsToRemove.isEmpty {
                    Logger.info("Removing \(signalAccountsToRemove.count) old SignalAccounts.")
                    for signalAccount in signalAccountsToRemove {
                        Logger.verbose("Removing old SignalAccount: \(signalAccount.recipientAddress)")
                        signalAccount.anyRemove(transaction: transaction)
                    }
                }

                if signalAccountsToUpsert.count > 0 {
                    Logger.info("Saving \(signalAccountsToUpsert.count) SignalAccounts.")
                    for signalAccount in signalAccountsToUpsert {
                        Logger.verbose("Saving SignalAccount: \(signalAccount.recipientAddress)")
                        signalAccount.anyUpsert(transaction: transaction)
                    }
                }

                let signalAccountCount = SignalAccount.anyCount(transaction: transaction)
                Logger.info("SignalAccount cache size: \(signalAccountCount).")

                // Add system contacts to the profile whitelist immediately so that they do
                // not see the "message request" UI.
                Self.profileManager.addUsers(
                    toProfileWhitelist: Array(seenAddresses.union(signalAccountsToKeep.keys)),
                    userProfileWriter: UserProfileWriter.systemContactsFetch,
                    transaction: transaction
                )

#if DEBUG
                let persistedAddresses = SignalAccount.anyFetchAll(transaction: transaction).map {
                    $0.recipientAddress
                }
                let persistedAddressSet = Set(persistedAddresses)
                owsAssertDebug(persistedAddresses.count == persistedAddressSet.count)
#endif
            }

            // Once we've persisted new SignalAccount state, we should let
            // StorageService know.
            Self.updateStorageServiceForSystemContactsFetch(
                allSignalAccountsBeforeFetch: persistedSignalAccountMap,
                allSignalAccountsAfterFetch: signalAccountsToKeep
            )

            let didChangeAnySignalAccount = !signalAccountsToRemove.isEmpty || !signalAccountsToUpsert.isEmpty
            DispatchQueue.main.async {
                // Post a notification if something changed or this is the first load since launch.
                let shouldNotify = didChangeAnySignalAccount || !self.hasLoadedSystemContacts
                self.hasLoadedSystemContacts = true
                self.contactsManagerCache.setSortedSignalAccounts(
                    self.sortSignalAccountsWithSneakyTransaction(Array(signalAccountsToKeep.values))
                )
                if shouldNotify {
                    NotificationCenter.default.postNotificationNameAsync(.OWSContactsManagerSignalAccountsDidChange, object: nil)
                }
            }
        }
    }

    /// Updates StorageService records for any Signal contacts associated with
    /// a system contact that has been added, removed, or modified in a
    /// relevant way. Has no effect when we are a linked device.
    private static func updateStorageServiceForSystemContactsFetch(
        allSignalAccountsBeforeFetch: [SignalServiceAddress: SignalAccount],
        allSignalAccountsAfterFetch: [SignalServiceAddress: SignalAccount]
    ) {
        guard tsAccountManager.isPrimaryDevice else {
            Logger.info("Skipping updating StorageService on contact change, not primary device!")
            return
        }

        /// Creates a mapping of addresses to system contacts, given an existing
        /// mapping of addresses to ``SignalAccount``s.
        func extractSystemContacts(
            accounts: [SignalServiceAddress: SignalAccount]
        ) -> (
            mapping: [SignalServiceAddress: Contact],
            addresses: Set<SignalServiceAddress>
        ) {
            let mapping = accounts.reduce(into: [SignalServiceAddress: Contact]()) { partialResult, kv in
                let (address, account) = kv

                guard
                    let contact = account.contact,
                    contact.isFromLocalAddressBook
                else {
                    return
                }

                partialResult[address] = contact
            }

            return (mapping: mapping, addresses: Set(mapping.keys))
        }

        let systemContactsBeforeFetch = extractSystemContacts(accounts: allSignalAccountsBeforeFetch)
        let systemContactsAfterFetch = extractSystemContacts(accounts: allSignalAccountsAfterFetch)

        var addressesToUpdateInStorageService: Set<SignalServiceAddress> = []

        // System contacts that are not present both before and after the fetch
        // were either removed or added. In both cases, we should update their
        // StorageService records.
        //
        // Note that just because a system contact was removed does *not* mean
        // we should remove the ContactRecord from StorageService. Rather, we
        // want to update the ContactRecord to reflect the removed system
        // contact details.
        let addedOrRemovedSystemContactAddresses = systemContactsAfterFetch.addresses
            .symmetricDifference(systemContactsBeforeFetch.addresses)

        addressesToUpdateInStorageService.formUnion(addedOrRemovedSystemContactAddresses)

        // System contacts present both before and after may have been updated
        // in a StorageService-relevant way. If so, we should let StorageService
        // know.
        let possiblyUpdatedSystemContactAddresses = systemContactsAfterFetch.addresses
            .intersection(systemContactsBeforeFetch.addresses)

        for address in possiblyUpdatedSystemContactAddresses {
            let contactBefore = systemContactsBeforeFetch.mapping[address]!
            let contactAfter = systemContactsAfterFetch.mapping[address]!

            if !contactBefore.namesAreEqual(toOther: contactAfter) {
                addressesToUpdateInStorageService.insert(address)
            }
        }

        storageServiceManager.recordPendingUpdates(updatedAddresses: Array(addressesToUpdateInStorageService))
    }
}

// MARK: - Intersection

@objc
extension OWSContactsManager {
    func intersectContacts(
        _ phoneNumbers: Set<String>,
        retryDelaySeconds: TimeInterval,
        success: @escaping (Set<SignalRecipient>) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        owsAssertDebug(!phoneNumbers.isEmpty)
        owsAssertDebug(retryDelaySeconds > 0)

        firstly {
            contactDiscoveryManager.lookUp(
                phoneNumbers: phoneNumbers,
                mode: .contactIntersection
            )
        }.done(on: .global()) { signalRecipients in
            Logger.info("Successfully intersected contacts.")
            success(signalRecipients)
        }.`catch`(on: .global()) { error in
            var retryAfter: TimeInterval = retryDelaySeconds

            if let cdsError = error as? ContactDiscoveryError {
                guard cdsError.code != ContactDiscoveryError.Kind.rateLimit.rawValue else {
                    Logger.error("Contact intersection hit rate limit with error: \(error)")
                    failure(error)
                    return
                }
                guard cdsError.retrySuggested else {
                    Logger.error("Contact intersection error suggests not to retry. Aborting without rescheduling.")
                    failure(error)
                    return
                }
                if let retryAfterDate = cdsError.retryAfterDate {
                    retryAfter = max(retryAfter, retryAfterDate.timeIntervalSinceNow)
                }
            }

            // TODO: Abort if another contact intersection succeeds in the meantime.
            Logger.warn("Contact intersection failed with error: \(error). Rescheduling.")
            DispatchQueue.global().asyncAfter(deadline: .now() + retryAfter) {
                self.intersectContacts(phoneNumbers, retryDelaySeconds: retryDelaySeconds * 2, success: success, failure: failure)
            }
        }
    }
}

// MARK: -

@objc
public extension OWSContactsManager {

    @nonobjc
    private static let unknownAddressFetchDateMap = AtomicDictionary<UUID, Date>()

    @objc(fetchProfileForUnknownAddress:)
    func fetchProfile(forUnknownAddress address: SignalServiceAddress) {
        guard let uuid = address.uuid else {
            return
        }
        let minFetchInterval = kMinuteInterval * 30
        if let lastFetchDate = Self.unknownAddressFetchDateMap[uuid],
           abs(lastFetchDate.timeIntervalSinceNow) < minFetchInterval {
            return
        }

        Self.unknownAddressFetchDateMap[uuid] = Date()

        bulkProfileFetch.fetchProfile(address: address)
    }
}

// MARK: -

public extension Array where Element == SignalAccount {
    func stableSort() -> [SignalAccount] {
        // Use an arbitrary sort but ensure the ordering is stable.
        self.sorted { (left, right) in
            left.recipientAddress.sortKey < right.recipientAddress.sortKey
        }
    }
}

// MARK: -

extension OWSContactsManager {

    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        contactsManagerCache.unsortedSignalAccounts(transaction: transaction)
    }

    // Order respects the systems contact sorting preference.
    @objc
    public func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        contactsManagerCache.sortedSignalAccounts(transaction: transaction)
    }

    @objc
    public func sortedSignalAccountsWithSneakyTransaction() -> [SignalAccount] {
        databaseStorage.read { transaction in
            sortedSignalAccounts(transaction: transaction)
        }
    }

    private static func removeLocalContact(contacts: [Contact],
                                           transaction: SDSAnyReadTransaction) -> [Contact] {
        let localNumber: String? = tsAccountManager.localNumber(with: transaction)

        var contactIdSet = Set<String>()
        return contacts.compactMap { contact in
            // Skip local contacts.
            func isLocalContact() -> Bool {
                for phoneNumber in contact.parsedPhoneNumbers {
                    if phoneNumber.toE164() == localNumber {
                        return true
                    }
                }
                return false
            }
            guard !isLocalContact() else {
                return nil
            }
            // De-deduplicate.
            guard !contactIdSet.contains(contact.uniqueId) else {
                return nil
            }
            contactIdSet.insert(contact.uniqueId)
            return contact
        }
    }

    @objc
    public func allUnsortedContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        Self.removeLocalContact(contacts: contactsManagerCache.allContacts(transaction: transaction),
                                transaction: transaction)
    }

    @objc
    public func allSortedContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        let contacts = (allUnsortedContacts(transaction: transaction) as NSArray)
        let comparator = Contact.comparatorSortingNames(byFirstThenLast: self.shouldSortByGivenName)
        return contacts.sortedArray(options: [], usingComparator: comparator) as! [Contact]
    }

    @objc
    public func comparableNameForSignalAccountWithSneakyTransaction(_ signalAccount: SignalAccount) -> String {
        databaseStorage.read { transaction in
            self.comparableName(for: signalAccount, transaction: transaction)
        }
    }

    @objc
    public func displayName(forSignalAccount signalAccount: SignalAccount,
                            transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: signalAccount.recipientAddress, transaction: transaction)
    }

    @objc
    public func displayNameForSignalAccountWithSneakyTransaction(_ signalAccount: SignalAccount) -> String {
        databaseStorage.read { transaction in
            self.displayName(forSignalAccount: signalAccount, transaction: transaction)
        }
    }

    // This is based on -[OWSContactsManager displayNameForAddress:transaction:].
    // Rather than being called once for each address, we call it once with all the
    // addresses and it will use a single database query per step to assign
    // display names to addresses using different techniques.
    private func displayNamesRefinery(
        for addresses: [SignalServiceAddress],
        transaction: SDSAnyReadTransaction
    ) -> Refinery<SignalServiceAddress, String> {
        return .init(addresses).refine { addresses in
            // Prefer a saved name from system contacts, if available.
            return cachedContactNames(for: addresses, transaction: transaction)
        }.refine { addresses in
            profileManager.fullNames(forAddresses: Array(addresses),
                                     transaction: transaction).sequenceWithNils
        }.refine { addresses in
            return self.phoneNumbers(for: Array(addresses),
                                     transaction: transaction).lazy.map {
                return $0?.nilIfEmpty
            }
        }.refine { addresses in
            return self.profileManager.usernames(forAddresses: Array(addresses), transaction: transaction).map { maybeUsername in
                guard let username = maybeUsername.stringOrNil else {
                    return nil
                }
                return CommonFormats.formatUsername(username)
            }
        }.refine { addresses in
            return addresses.lazy.map {
                self.fetchProfile(forUnknownAddress: $0)
                return self.unknownUserLabel
            }
        }
    }

    @objc
    public func displayNamesByAddress(
        for addresses: [SignalServiceAddress],
        transaction: SDSAnyReadTransaction
    ) -> [SignalServiceAddress: String] {
        Dictionary(displayNamesRefinery(for: addresses, transaction: transaction))
    }

    @objc(objc_displayNamesForAddresses:transaction:)
    func displayNames(for addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [String] {
        displayNamesRefinery(for: addresses, transaction: transaction).values.map { $0! }
    }

    func phoneNumbers(for addresses: [SignalServiceAddress],
                      transaction: SDSAnyReadTransaction) -> [String?] {
        return Refinery<SignalServiceAddress, String>(addresses).refine {
            return $0.map { $0.phoneNumber?.filterStringForDisplay() }
        }.refine { (addresses: AnySequence<SignalServiceAddress>) -> [String?] in
            let accounts = fetchSignalAccounts(for: addresses, transaction: transaction)
            return accounts.map { maybeAccount in
                return maybeAccount?.recipientPhoneNumber?.filterStringForDisplay()
            }
        }.values
    }

    func fetchSignalAccounts(for addresses: AnySequence<SignalServiceAddress>,
                             transaction: SDSAnyReadTransaction) -> [SignalAccount?] {
        return modelReadCaches.signalAccountReadCache.getSignalAccounts(addresses: addresses, transaction: transaction)
    }

    @objc(cachedContactNameForAddress:transaction:)
    func cachedContactName(for address: SignalServiceAddress, trasnaction: SDSAnyReadTransaction) -> String? {
        return cachedContactNames(for: AnySequence([address]), transaction: trasnaction)[0]
    }

    func cachedContactNames(for addresses: AnySequence<SignalServiceAddress>,
                            transaction: SDSAnyReadTransaction) -> [String?] {
        // First, get full names from accounts where possible.
        let accounts = fetchSignalAccounts(for: addresses, transaction: transaction)
        let accountFullNames = accounts.lazy.map { $0?.fullName }

        // Build a list of addreses that don't have accounts. Leave nil placeholders for those
        // addresses that don't need to be queried so that we can keep all our arrays parallel.
        let addressesToQuery = zip(addresses, accounts).map { tuple -> SignalServiceAddress? in
            let (address, account) = tuple
            if account != nil {
                return nil
            }
            return address
        }

        // Do a batch lookup of phone numbers for addresses that don't have accounts and use the cache of Contacts
        // to get their names.
        let phoneNumberFullNames = Refinery<SignalServiceAddress?, String>(addressesToQuery).refineNonnilKeys { (addresses: AnySequence<SignalServiceAddress>) -> [String?] in
            let phoneNumbers = phoneNumbers(for: Array(addresses), transaction: transaction)
            return phoneNumbers.map { (maybePhoneNumber: String?) -> String? in
                guard let phoneNumber = maybePhoneNumber else {
                    return nil
                }
                // Fast (in-memory) lookup of a non-Signal contact. For example, no-longer-registered Signal users.
                return contact(forPhoneNumber: phoneNumber, transaction: transaction)?.fullName
            }
        }.values

        // At this point each address will either have a full name from its account, from its phone number, or neither.
        // Return the nonnil value for each if one exists.
        return zip(accountFullNames, phoneNumberFullNames).map { tuple in
            return tuple.0 ?? tuple.1
        }
    }
}

private extension SignalAccount {
    var fullName: String? {
        // Name may be either the nickname or the full name of the contact
        guard let fullName = contactPreferredDisplayName()?.nilIfEmpty else {
            return nil
        }
        guard let label = multipleAccountLabelText.nilIfEmpty else {
            return fullName
        }
        return "\(fullName) (\(label))"
    }
}
