//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// MARK: - OWSContactsMangerSwiftValues

class OWSContactsManagerSwiftValues {

    fileprivate var systemContactsCache: SystemContactsCache?

    fileprivate let systemContactsDataProvider = AtomicOptional<SystemContactsDataProvider>(nil)

    fileprivate var primaryDeviceSystemContactsDataProvider: PrimaryDeviceSystemContactsDataProvider? {
        systemContactsDataProvider.get() as? PrimaryDeviceSystemContactsDataProvider
    }

    fileprivate let usernameLookupManager: UsernameLookupManager

    init(usernameLookupManager: UsernameLookupManager) {
        self.usernameLookupManager = usernameLookupManager
    }
}

// MARK: Build for ObjC

extension OWSContactsManagerSwiftValues {
    /// This method allows ObjC code to get an instance of this class, without
    /// exposing the Swift-only types required by the constructor. Note that
    /// this method will fail if ``DependenciesBridge`` has not yet been
    /// created.
    static func makeWithValuesFromDependenciesBridge() -> OWSContactsManagerSwiftValues {
        .init(usernameLookupManager: DependenciesBridge.shared.usernameLookupManager)
    }
}

// MARK: - Some caches

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

    func blurAvatar(_ image: UIImage) -> UIImage? {
        do {
            return try image.withGaussianBlur(radius: 16, resizeToMaxPixelDimension: 100)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Sorting

    @objc
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
           let contact = contact(forPhoneNumber: phoneNumber, transaction: transaction),
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
    static let intersectionQueue = DispatchQueue(label: "org.signal.contacts.intersection")
    @objc
    var intersectionQueue: DispatchQueue { Self.intersectionQueue }

    private static func buildContactAvatarHash(contact: Contact) -> Data? {
        return autoreleasepool {
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
    }

    private static func buildSignalAccounts(
        for systemContacts: [Contact],
        transaction: SDSAnyReadTransaction
    ) -> [SignalAccount] {
        var signalAccounts = [SignalAccount]()
        var seenAddresses = Set<SignalServiceAddress>()
        for contact in systemContacts {
            var signalRecipients = contact.signalRecipients(transaction: transaction)
            guard !signalRecipients.isEmpty else {
                continue
            }
            // TODO: Confirm ordering.
            signalRecipients.sort { $0.address.compare($1.address) == .orderedAscending }
            for signalRecipient in signalRecipients {
                if seenAddresses.contains(signalRecipient.address) {
                    continue
                }
                seenAddresses.insert(signalRecipient.address)

                let multipleAccountLabelText = contact.uniquePhoneNumberLabel(
                    for: signalRecipient.address,
                    relatedAddresses: signalRecipients.map { $0.address }
                )
                let contactAvatarHash = Self.buildContactAvatarHash(contact: contact)
                let signalAccount = SignalAccount(
                    contact: contact,
                    contactAvatarHash: contactAvatarHash,
                    multipleAccountLabelText: multipleAccountLabelText,
                    recipientPhoneNumber: signalRecipient.address.phoneNumber,
                    recipientUUID: signalRecipient.address.uuidString)
                signalAccounts.append(signalAccount)
            }
        }
        return signalAccounts.stableSort()
    }

    @objc
    func buildSignalAccountsAndUpdatePersistedState(forFetchedSystemContacts localSystemContacts: [Contact]) {
        intersectionQueue.async {
            let (oldSignalAccounts, newSignalAccounts) = Self.databaseStorage.read { transaction in
                let oldSignalAccounts = SignalAccount.anyFetchAll(transaction: transaction)
                let newSignalAccounts = Self.buildSignalAccounts(for: localSystemContacts, transaction: transaction)
                return (oldSignalAccounts, newSignalAccounts)
            }
            let oldSignalAccountsMap: [SignalServiceAddress: SignalAccount] = Dictionary(
                oldSignalAccounts.lazy.map { ($0.recipientAddress, $0) },
                uniquingKeysWith: { _, new in new }
            )
            var newSignalAccountsMap = [SignalServiceAddress: SignalAccount]()

            var signalAccountsToInsert = [SignalAccount]()
            for newSignalAccount in newSignalAccounts {
                let address = newSignalAccount.recipientAddress

                // The user might have multiple entries in their address book with the same phone number.
                if newSignalAccountsMap[address] != nil {
                    Logger.warn("Ignoring redundant signal account: \(address)")
                    continue
                }

                let oldSignalAccountToKeep: SignalAccount?
                switch oldSignalAccountsMap[address] {
                case .none:
                    oldSignalAccountToKeep = nil

                case .some(let oldSignalAccount) where oldSignalAccount.hasSameContent(newSignalAccount):
                    // Same content, no need to update.
                    oldSignalAccountToKeep = oldSignalAccount

                case .some:
                    oldSignalAccountToKeep = nil
                }

                if let oldSignalAccount = oldSignalAccountToKeep {
                    newSignalAccountsMap[address] = oldSignalAccount
                } else {
                    newSignalAccountsMap[address] = newSignalAccount
                    signalAccountsToInsert.append(newSignalAccount)
                }
            }

            // Clean up orphans.
            var signalAccountsToRemove = [SignalAccount]()
            for signalAccount in oldSignalAccounts {
                if newSignalAccountsMap[signalAccount.recipientAddress]?.uniqueId == signalAccount.uniqueId {
                    // If the SignalAccount is going to be inserted or updated, it doesn't need
                    // to be cleaned up.
                    continue
                }
                // Clean up instances that have been replaced by another instance or are no
                // longer in the system contacts.
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

                if signalAccountsToInsert.count > 0 {
                    Logger.info("Saving \(signalAccountsToInsert.count) SignalAccounts.")
                    for signalAccount in signalAccountsToInsert {
                        Logger.verbose("Saving SignalAccount: \(signalAccount.recipientAddress)")
                        signalAccount.anyInsert(transaction: transaction)
                    }
                }

                Logger.info("SignalAccount count: \(newSignalAccountsMap.count).")

                // Add system contacts to the profile whitelist immediately so that they do
                // not see the "message request" UI.
                Self.profileManager.addUsers(
                    toProfileWhitelist: Array(newSignalAccountsMap.keys),
                    userProfileWriter: .systemContactsFetch,
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
                allSignalAccountsBeforeFetch: oldSignalAccountsMap,
                allSignalAccountsAfterFetch: newSignalAccountsMap
            )

            let didChangeAnySignalAccount = !signalAccountsToRemove.isEmpty || !signalAccountsToInsert.isEmpty
            DispatchQueue.main.async {
                // Post a notification if something changed or this is the first load since launch.
                let shouldNotify = didChangeAnySignalAccount || !self.hasLoadedSystemContacts
                self.hasLoadedSystemContacts = true
                self.swiftValues.systemContactsCache?.unsortedSignalAccounts.set(Array(newSignalAccountsMap.values))
                self.didUpdateSignalAccounts(shouldClearCache: false, shouldNotify: shouldNotify)
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

                guard let contact = account.contact else {
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

    func didUpdateSignalAccounts(transaction: SDSAnyWriteTransaction) {
        transaction.addTransactionFinalizationBlock(forKey: "OWSContactsManager.didUpdateSignalAccounts") { _ in
            self.didUpdateSignalAccounts(shouldClearCache: true, shouldNotify: true)
        }
    }

    private func didUpdateSignalAccounts(shouldClearCache: Bool, shouldNotify: Bool) {
        if shouldClearCache {
            swiftValues.systemContactsCache?.unsortedSignalAccounts.set(nil)
        }
        if shouldNotify {
            NotificationCenter.default.postNotificationNameAsync(.OWSContactsManagerSignalAccountsDidChange, object: nil)
        }
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
        }.done(on: DispatchQueue.global()) { signalRecipients in
            Logger.info("Successfully intersected contacts.")
            success(signalRecipients)
        }.`catch`(on: DispatchQueue.global()) { error in
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

public extension OWSContactsManager {

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

// MARK: System Contacts

private class SystemContactsCache {
    let unsortedSignalAccounts = AtomicOptional<[SignalAccount]>(nil)
    let contactsMaps = AtomicOptional<ContactsMaps>(nil)
}

extension OWSContactsManager {
    @objc
    func setUpSystemContacts() {
        updateSystemContactsDataProvider()
        registerForRegistrationStateNotification()
        if CurrentAppContext().isMainApp {
            warmSystemContactsCache()
        }
    }

    public func setIsPrimaryDevice() {
        updateSystemContactsDataProvider(forcePrimary: true)
    }

    private func registerForRegistrationStateNotification() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
    }

    @objc
    private func registrationStateDidChange() {
        updateSystemContactsDataProvider()
    }

    private func updateSystemContactsDataProvider(forcePrimary: Bool = false) {
        let dataProvider: SystemContactsDataProvider?
        if forcePrimary {
            dataProvider = PrimaryDeviceSystemContactsDataProvider()
        } else if !tsAccountManager.isRegistered {
            dataProvider = nil
        } else if tsAccountManager.isPrimaryDevice {
            dataProvider = PrimaryDeviceSystemContactsDataProvider()
        } else {
            dataProvider = LinkedDeviceSystemContactsDataProvider()
        }
        swiftValues.systemContactsDataProvider.set(dataProvider)
    }

    private func warmSystemContactsCache() {
        let systemContactsCache = SystemContactsCache()
        swiftValues.systemContactsCache = systemContactsCache

        InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmSystemContactsCache") {
            databaseStorage.read {
                var phoneNumberCount = 0
                if let dataProvider = swiftValues.systemContactsDataProvider.get() {
                    let contactsMaps = buildContactsMaps(using: dataProvider, transaction: $0)
                    systemContactsCache.contactsMaps.set(contactsMaps)
                    phoneNumberCount = contactsMaps.phoneNumberToContactMap.count
                }

                let unsortedSignalAccounts = fetchUnsortedSignalAccounts(transaction: $0)
                systemContactsCache.unsortedSignalAccounts.set(unsortedSignalAccounts)
                let signalAccountCount = unsortedSignalAccounts.count

                Logger.info("There are \(phoneNumberCount) phone numbers and \(signalAccountCount) SignalAccounts.")
            }
        }
    }

    @objc
    public func contact(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact? {
        if let cachedValue = swiftValues.systemContactsCache?.contactsMaps.get() {
            return cachedValue.phoneNumberToContactMap[phoneNumber]
        }
        guard let dataProvider = swiftValues.systemContactsDataProvider.get() else {
            owsFailDebug("Can't access contacts until registration is finished.")
            return nil
        }
        return dataProvider.fetchSystemContact(for: phoneNumber, transaction: transaction)
    }

    private func buildContactsMaps(
        using dataProvider: SystemContactsDataProvider,
        transaction: SDSAnyReadTransaction
    ) -> ContactsMaps {
        let systemContacts = dataProvider.fetchAllSystemContacts(transaction: transaction)
        let localNumber = tsAccountManager.localNumber(with: transaction)
        return ContactsMaps.build(contacts: systemContacts, localNumber: localNumber)
    }

    @objc
    func setContactsMaps(_ contactsMaps: ContactsMaps, localNumber: String?, transaction: SDSAnyWriteTransaction) {
        guard let dataProvider = swiftValues.primaryDeviceSystemContactsDataProvider else {
            return owsFailDebug("Can't modify contacts maps on linked devices.")
        }
        let oldContactsMaps = swiftValues.systemContactsCache?.contactsMaps.swap(contactsMaps)
        dataProvider.setContactsMaps(
            contactsMaps,
            oldContactsMaps: { oldContactsMaps ?? buildContactsMaps(using: dataProvider, transaction: transaction) },
            localNumber: localNumber,
            transaction: transaction
        )
    }

    private func fetchUnsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        SignalAccount.anyFetchAll(transaction: transaction)
    }

    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        if let cachedValue = swiftValues.systemContactsCache?.unsortedSignalAccounts.get() {
            return cachedValue
        }
        let uncachedValue = fetchUnsortedSignalAccounts(transaction: transaction)
        swiftValues.systemContactsCache?.unsortedSignalAccounts.set(uncachedValue)
        return uncachedValue
    }

    private func allUnsortedContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        guard let dataProvider = swiftValues.systemContactsDataProvider.get() else {
            owsFailDebug("Can't access contacts until registration is finished.")
            return []
        }
        let localNumber = tsAccountManager.localNumber(with: transaction)
        return dataProvider.fetchAllSystemContacts(transaction: transaction)
            .filter { !$0.hasPhoneNumber(localNumber) }
    }

    public func allSortedContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        allUnsortedContacts(transaction: transaction)
            .sorted { comparableName(for: $0).caseInsensitiveCompare(comparableName(for: $1)) == .orderedAscending }
    }
}

// MARK: - Contact Names

extension OWSContactsManager {
    @objc
    public func comparableNameForSignalAccountWithSneakyTransaction(_ signalAccount: SignalAccount) -> String {
        databaseStorage.read { transaction in
            self.comparableName(for: signalAccount, transaction: transaction)
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
        }.refine { addresses -> [String?] in
            swiftValues.usernameLookupManager.fetchUsernames(
                forAddresses: addresses,
                transaction: transaction.asV2Read
            )
        }.refine { addresses in
            return addresses.lazy.map {
                self.fetchProfile(forUnknownAddress: $0)
                return self.unknownUserLabel
            }
        }
    }

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
        guard let fullName = contactPreferredDisplayName() else {
            return nil
        }
        guard let label = multipleAccountLabelText.nilIfEmpty else {
            return fullName
        }
        return "\(fullName) (\(label))"
    }
}

extension ContactsManagerProtocol {
    public func nameForAddress(_ address: SignalServiceAddress,
                               localUserDisplayMode: LocalUserDisplayMode,
                               short: Bool,
                               transaction: SDSAnyReadTransaction) -> NSAttributedString {
        let name: String
        if address.isLocalAddress {
            switch localUserDisplayMode {
            case .noteToSelf:
                name = MessageStrings.noteToSelf
            case .asLocalUser:
                name = CommonStrings.you
            case .asUser:
                if short {
                    name = shortDisplayName(for: address,
                                            transaction: transaction)
                } else {
                    name = displayName(for: address,
                                       transaction: transaction)
                }
            }
        } else {
            if short {
                name = shortDisplayName(for: address,
                                        transaction: transaction)
            } else {
                name = displayName(for: address,
                                   transaction: transaction)
            }
        }
        return name.asAttributedString
    }
}
