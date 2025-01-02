//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
import CryptoKit
import Foundation
import LibSignalClient

extension Notification.Name {
    public static let OWSContactsManagerSignalAccountsDidChange = Notification.Name("OWSContactsManagerSignalAccountsDidChangeNotification")
    public static let OWSContactsManagerContactsDidChange = Notification.Name("OWSContactsManagerContactsDidChangeNotification")
}

@objc
public enum RawContactAuthorizationStatus: UInt {
    case notDetermined, denied, restricted, limited, authorized
}

public enum ContactAuthorizationForEditing {
    // Contact edit access not supported by this device (e.g. a linked device)
    case notAllowed
    // Contact edit access explicitly denied by user
    case notAuthorized
    // Contact read access explicitly allowed by user to some or all of the system contacts.
    // In both of these situations, the user can write to system contacts.
    case authorized
}

public enum ContactAuthorizationForSyncing {
    // Contact edit access not supported by this device (e.g. a linked device)
    case notAllowed
    // Contact edit access explicitly denied by user
    case denied
    // Contact access restricted by actions outside the control of the user (see CNAuthorizationStatus.restricted)
    case restricted
    // Contact read access explicitly allowed by user to all of the system contacts.
    case authorized
    // Contact read access explicitly allowed by user to some of the system contacts.
    case limited
}

public enum ContactAuthorizationForSharing {
    // Authorization hasn't yet been requested
    case notDetermined
    // Contact read access explicitly denied by user
    case denied
    // Some type of contact read access explicitly allowed by user
    case authorized
}

public class OWSContactsManager: NSObject, ContactsManagerProtocol {
    private let avatarBlurringCache = LowTrustCache()
    private let cnContactCache = LRUCache<String, CNContact>(maxSize: 50, shouldEvacuateInBackground: true)
    private let isInWhitelistedGroupWithLocalUserCache = AtomicDictionary<ServiceId, Bool>([:], lock: .init())
    private let hasWhitelistedGroupMemberCache = AtomicDictionary<Data, Bool>([:], lock: .init())
    private let systemContactsCache = SystemContactsCache()
    private let unknownThreadWarningCache = LowTrustCache()

    private let intersectionQueue = DispatchQueue(label: "org.signal.contacts.intersection")

    private let keyValueStore = KeyValueStore(collection: "OWSContactsManagerCollection")
    private let skipContactAvatarBlurByServiceIdStore = KeyValueStore(collection: "OWSContactsManager.skipContactAvatarBlurByUuidStore")
    private let skipGroupAvatarBlurByGroupIdStore = KeyValueStore(collection: "OWSContactsManager.skipGroupAvatarBlurByGroupIdStore")

    private let nicknameManager: any NicknameManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let systemContactsFetcher: SystemContactsFetcher
    private let usernameLookupManager: UsernameLookupManager

    public var isEditingAllowed: Bool {
        // We're only allowed to edit contacts on devices that can sync them. Otherwise the UX doesn't make sense.
        return isSyncingAllowed
    }

    public var isSyncingAllowed: Bool {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        return tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false
    }

    /// Must call `requestSystemContactsOnce` before accessing this method
    public var editingAuthorization: ContactAuthorizationForEditing {
        guard isEditingAllowed else {
            return .notAllowed
        }
        switch systemContactsFetcher.rawAuthorizationStatus {
        case .notDetermined:
            owsFailDebug("should have called `requestOnce` before checking authorization status.")
            fallthrough
        case .denied, .restricted:
            return .notAuthorized
        case .authorized, .limited:
            return .authorized
        }
    }

    /// Must call `requestSystemContactsOnce` before accessing this method
    public var syncingAuthorization: ContactAuthorizationForSyncing {
        guard isSyncingAllowed else {
            return .notAllowed
        }
        switch systemContactsFetcher.rawAuthorizationStatus {
        case .notDetermined:
            owsFailDebug("should have called `requestOnce` before checking authorization status.")
            fallthrough
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .limited:
            return .limited
        case .authorized:
            return .authorized
        }
    }

    public var sharingAuthorization: ContactAuthorizationForSharing {
        switch self.systemContactsFetcher.rawAuthorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorized, .limited:
            return .authorized
        }
    }
    /// Whether or not we've fetched system contacts on this launch.
    ///
    /// This property is set to true even if the user doesn't have any system
    /// contacts.
    ///
    /// This property is only valid if the user has granted contacts access.
    /// Otherwise, it's value is undefined.
    public private(set) var hasLoadedSystemContacts: Bool = false

    public init(
        appReadiness: AppReadiness,
        nicknameManager: any NicknameManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        usernameLookupManager: any UsernameLookupManager
    ) {
        self.nicknameManager = nicknameManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.systemContactsFetcher = SystemContactsFetcher(appReadiness: appReadiness)
        self.usernameLookupManager = usernameLookupManager
        super.init()
        self.systemContactsFetcher.delegate = self
        SwiftSingletons.register(self)
    }

    // Request systems contacts and start syncing changes. The user will see an alert
    // if they haven't previously.
    public func requestSystemContactsOnce(completion: (((any Error)?) -> Void)? = nil) {
        AssertIsOnMainThread()

        guard isSyncingAllowed else {
            if let completion = completion {
                Logger.warn("Editing contacts isn't available on linked devices.")
                completion(OWSError.makeGenericError())
            }
            return
        }
        systemContactsFetcher.requestOnce(completion: completion)
    }

    /// Ensure's the app has the latest contacts, but won't prompt the user for contact
    /// access if they haven't granted it.
    public func fetchSystemContactsOnceIfAlreadyAuthorized() {
        guard isSyncingAllowed else {
            return
        }
        systemContactsFetcher.fetchOnceIfAlreadyAuthorized()
    }

    /// This variant will fetch system contacts if contact access has already been granted,
    /// but not prompt for contact access. Also, it will always notify delegates, even if
    /// contacts haven't changed, and will clear out any stale cached SignalAccounts
    public func userRequestedSystemContactsRefresh() -> Promise<Void> {
        guard isSyncingAllowed else {
            owsFailDebug("Editing contacts isn't available on linked devices.")
            return Promise<Void>(error: OWSError.makeAssertionError())
        }
        return Promise<Void> { future in
            self.systemContactsFetcher.userRequestedRefresh { error in
                if let error {
                    Logger.error("refreshing contacts failed with error: \(error)")
                    future.reject(error)
                } else {
                    future.resolve(())
                }
            }
        }
    }
}

// MARK: - SystemContactsFetcherDelegate

extension OWSContactsManager: SystemContactsFetcherDelegate {

    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, hasAuthorizationStatus authorizationStatus: RawContactAuthorizationStatus) {
        guard isEditingAllowed else {
            owsFailDebug("Syncing contacts isn't available on linked devices.")
            return
        }
        switch authorizationStatus {
        // TODO: [Contacts, iOS 18] Validate if limited contacts authorization is appropriate
        case .restricted, .denied, .limited:
            self.updateContacts(nil, isUserRequested: false)
        case .notDetermined, .authorized:
            break
        }
    }

    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, updatedContacts contacts: [SystemContact], isUserRequested: Bool) {
        guard isEditingAllowed else {
            owsFailDebug("Syncing contacts isn't available on linked devices.")
            return
        }
        updateContacts(contacts, isUserRequested: isUserRequested)
    }

    public func displayNameString(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        displayName(for: address, tx: transaction).resolvedValue()
    }

    public func shortDisplayNameString(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        displayName(for: address, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
    }
}

// MARK: -

private class SystemContactsCache {
    let fetchedSystemContacts = AtomicOptional<FetchedSystemContacts>(nil, lock: .init())
}

// MARK: -

private class LowTrustCache {
    let contactCache = AtomicSet<ServiceId>(lock: .sharedGlobal)
    let groupCache = AtomicSet<Data>(lock: .sharedGlobal)

    func contains(groupThread: TSGroupThread) -> Bool {
        groupCache.contains(groupThread.groupId)
    }

    func contains(contactThread: TSContactThread) -> Bool {
        contains(address: contactThread.contactAddress)
    }

    func contains(address: SignalServiceAddress) -> Bool {
        guard let serviceId = address.serviceId else {
            return false
        }
        return contactCache.contains(serviceId)
    }

    func add(groupThread: TSGroupThread) {
        groupCache.insert(groupThread.groupId)
    }

    func add(contactThread: TSContactThread) {
        add(address: contactThread.contactAddress)
    }

    func add(address: SignalServiceAddress) {
        guard let serviceId = address.serviceId else {
            return
        }
        contactCache.insert(serviceId)
    }
}

// MARK: -

extension OWSContactsManager: ContactManager {
    // MARK: Low Trust

    private func isLowTrustThread(_ thread: TSThread, lowTrustCache: LowTrustCache, tx: SDSAnyReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isLowTrustContact(contactThread: contactThread, lowTrustCache: lowTrustCache, tx: tx)
        } else if let groupThread = thread as? TSGroupThread {
            return isLowTrustGroup(groupThread: groupThread, lowTrustCache: lowTrustCache, tx: tx)
        } else {
            owsFailDebug("Invalid thread.")
            return false
        }
    }

    private func isLowTrustContact(address: SignalServiceAddress, lowTrustCache: LowTrustCache, tx: SDSAnyReadTransaction) -> Bool {
        if lowTrustCache.contains(address: address) {
            return false
        }
        guard let contactThread = TSContactThread.getWithContactAddress(address, transaction: tx) else {
            lowTrustCache.add(address: address)
            return false
        }
        return isLowTrustContact(contactThread: contactThread, lowTrustCache: lowTrustCache, tx: tx)
    }

    private func isLowTrustContact(contactThread: TSContactThread, lowTrustCache: LowTrustCache, tx: SDSAnyReadTransaction) -> Bool {
        let address = contactThread.contactAddress
        if lowTrustCache.contains(address: address) {
            return false
        }
        if !contactThread.hasPendingMessageRequest(transaction: tx) {
            lowTrustCache.add(address: address)
            return false
        }
        // ...and not in a whitelisted group with the locar user.
        if isInWhitelistedGroupWithLocalUser(otherAddress: address, tx: tx) {
            lowTrustCache.add(address: address)
            return false
        }
        // We can skip avatar blurring if the user has explicitly waived the blurring.
        if
            lowTrustCache === avatarBlurringCache,
            let storeKey = address.serviceId?.serviceIdUppercaseString,
            skipContactAvatarBlurByServiceIdStore.getBool(storeKey, defaultValue: false, transaction: tx.asV2Read)
        {
            lowTrustCache.add(address: address)
            return false
        }
        return true
    }

    private func isLowTrustGroup(groupThread: TSGroupThread, lowTrustCache: LowTrustCache, tx: SDSAnyReadTransaction) -> Bool {
        if lowTrustCache.contains(groupThread: groupThread) {
            return false
        }
        if !groupThread.hasPendingMessageRequest(transaction: tx) {
            lowTrustCache.add(groupThread: groupThread)
            return false
        }
        // We can skip "unknown thread warnings" if a group has members which are trusted.
        if lowTrustCache === unknownThreadWarningCache, hasWhitelistedGroupMember(groupThread: groupThread, tx: tx) {
            lowTrustCache.add(groupThread: groupThread)
            return false
        }
        return true
    }

    private func isInWhitelistedGroupWithLocalUser(otherAddress: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Bool {
        let cache = isInWhitelistedGroupWithLocalUserCache
        if let cacheKey = otherAddress.serviceId, let cachedValue = cache[cacheKey] {
            return cachedValue
        }
        let result: Bool = {
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
                owsFailDebug("Missing localAddress.")
                return false
            }
            let otherGroupThreadIds = TSGroupThread.groupThreadIds(with: otherAddress, transaction: tx)
            guard !otherGroupThreadIds.isEmpty else {
                return false
            }
            let localGroupThreadIds = TSGroupThread.groupThreadIds(with: localAddress, transaction: tx)
            let groupThreadIds = Set(otherGroupThreadIds).intersection(localGroupThreadIds)
            for groupThreadId in groupThreadIds {
                guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: tx) else {
                    owsFailDebug("Missing group thread")
                    continue
                }
                if SSKEnvironment.shared.profileManagerRef.isGroupId(inProfileWhitelist: groupThread.groupId, transaction: tx) {
                    return true
                }
            }
            return false
        }()
        if let cacheKey = otherAddress.serviceId {
            cache[cacheKey] = result
        }
        return result
    }

    private func hasWhitelistedGroupMember(groupThread: TSGroupThread, tx: SDSAnyReadTransaction) -> Bool {
        let cache = hasWhitelistedGroupMemberCache
        let cacheKey = groupThread.groupId
        if let cachedValue = cache[cacheKey] {
            return cachedValue
        }
        let result: Bool = {
            for groupMember in groupThread.groupMembership.fullMembers {
                if SSKEnvironment.shared.profileManagerRef.isUser(inProfileWhitelist: groupMember, transaction: tx) {
                    return true
                }
            }
            return false
        }()
        cache[cacheKey] = result
        return result
    }

    public func shouldShowUnknownThreadWarning(thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustThread(thread, lowTrustCache: unknownThreadWarningCache, tx: transaction)
    }

    // MARK: - Avatar Blurring

    public func shouldBlurContactAvatar(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustContact(address: address, lowTrustCache: avatarBlurringCache, tx: transaction)
    }

    public func shouldBlurContactAvatar(contactThread: TSContactThread, transaction: SDSAnyReadTransaction) -> Bool {
        isLowTrustContact(contactThread: contactThread, lowTrustCache: avatarBlurringCache, tx: transaction)
    }

    public func shouldBlurGroupAvatar(groupThread: TSGroupThread, transaction: SDSAnyReadTransaction) -> Bool {
        if nil == groupThread.groupModel.avatarHash {
            // DO NOT add to the cache.
            return false
        }

        if !isLowTrustGroup(
            groupThread: groupThread,
            lowTrustCache: avatarBlurringCache,
            tx: transaction
        ) {
            return false
        }

        // We can skip avatar blurring if the user has explicitly waived the blurring.
        if skipGroupAvatarBlurByGroupIdStore.getBool(
            groupThread.groupId.hexadecimalString,
            defaultValue: false,
            transaction: transaction.asV2Read
        ) {
            avatarBlurringCache.add(groupThread: groupThread)
            return false
        }

        return true
    }

    public static let skipContactAvatarBlurDidChange = NSNotification.Name("skipContactAvatarBlurDidChange")
    public static let skipContactAvatarBlurAddressKey = "skipContactAvatarBlurAddressKey"
    public static let skipGroupAvatarBlurDidChange = NSNotification.Name("skipGroupAvatarBlurDidChange")
    public static let skipGroupAvatarBlurGroupUniqueIdKey = "skipGroupAvatarBlurGroupUniqueIdKey"

    public func doNotBlurContactAvatar(address: SignalServiceAddress, transaction tx: SDSAnyWriteTransaction) {
        guard let serviceId = address.serviceId else {
            owsFailDebug("Missing ServiceId for user.")
            return
        }
        let storeKey = serviceId.serviceIdUppercaseString
        let shouldSkipBlur = skipContactAvatarBlurByServiceIdStore.getBool(storeKey, defaultValue: false, transaction: tx.asV2Read)
        guard !shouldSkipBlur else {
            owsFailDebug("Value did not change.")
            return
        }
        skipContactAvatarBlurByServiceIdStore.setBool(true, key: storeKey, transaction: tx.asV2Write)
        if let contactThread = TSContactThread.getWithContactAddress(address, transaction: tx) {
            SSKEnvironment.shared.databaseStorageRef.touch(thread: contactThread, shouldReindex: false, transaction: tx)
        }
        tx.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(
                Self.skipContactAvatarBlurDidChange,
                object: nil,
                userInfo: [
                    Self.skipContactAvatarBlurAddressKey: address
                ]
            )
        }
    }

    public func doNotBlurGroupAvatar(groupThread: TSGroupThread, transaction: SDSAnyWriteTransaction) {
        let groupId = groupThread.groupId
        let groupUniqueId = groupThread.uniqueId
        guard !skipGroupAvatarBlurByGroupIdStore.getBool(
            groupId.hexadecimalString,
            defaultValue: false,
            transaction: transaction.asV2Read
        ) else {
            owsFailDebug("Value did not change.")
            return
        }
        skipGroupAvatarBlurByGroupIdStore.setBool(
            true,
            key: groupId.hexadecimalString,
            transaction: transaction.asV2Write
        )
        SSKEnvironment.shared.databaseStorageRef.touch(thread: groupThread, shouldReindex: false, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(
                Self.skipGroupAvatarBlurDidChange,
                object: nil,
                userInfo: [
                    Self.skipGroupAvatarBlurGroupUniqueIdKey: groupUniqueId
                ]
            )
        }
    }

    public func blurAvatar(_ image: UIImage) -> UIImage? {
        do {
            return try image.withGaussianBlur(radius: 16, resizeToMaxPixelDimension: 100)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Avatars

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

    private func profileAvatarImageData(
        forAddress address: SignalServiceAddress?,
        shouldValidate: Bool,
        transaction: SDSAnyReadTransaction
    ) -> Data? {
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

        if let avatarData = SSKEnvironment.shared.profileManagerImplRef.profileAvatarData(for: address, transaction: transaction),
           let validData = validateIfNecessary(avatarData) {
            return validData
        }

        return nil
    }

    private func systemContactOrSyncedImageData(
        forAddress address: SignalServiceAddress?,
        shouldValidate: Bool,
        transaction: SDSAnyReadTransaction
    ) -> Data? {
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

        guard let address, address.isValid else {
            owsFailDebug("Missing or invalid address.")
            return nil
        }

        guard !address.isLocalAddress else {
            // Never use system contact or synced image data for the local user
            return nil
        }

        if
            let phoneNumber = address.phoneNumber,
            let signalAccount = self.fetchSignalAccount(forPhoneNumber: phoneNumber, transaction: transaction),
            let cnContactId = signalAccount.cnContactId,
            let avatarData = self.avatarData(for: cnContactId),
            let validData = validateIfNecessary(avatarData)
        {
            return validData
        }
        return nil
    }

    // MARK: - Intersection

    private func buildContactAvatarHash(for systemContact: SystemContact) -> Data? {
        return autoreleasepool {
            let cnContactId = systemContact.cnContactId
            guard let contactAvatarData = avatarData(for: cnContactId) else {
                return nil
            }
            return Data(SHA256.hash(data: contactAvatarData))
        }
    }

    private func discoverableRecipient(for canonicalPhoneNumber: CanonicalPhoneNumber, tx: SDSAnyReadTransaction) -> SignalRecipient? {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        for phoneNumber in [canonicalPhoneNumber.rawValue] + canonicalPhoneNumber.alternatePhoneNumbers() {
            let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx.asV2Read)
            guard let recipient, recipient.isPhoneNumberDiscoverable else {
                continue
            }
            return recipient
        }
        return nil
    }

    private func buildSignalAccounts(
        for fetchedSystemContacts: FetchedSystemContacts,
        transaction: SDSAnyReadTransaction
    ) -> [SignalAccount] {
        var discoverableRecipients = [CanonicalPhoneNumber: (SignalRecipient, ServiceId)]()
        var discoverablePhoneNumberCounts = [String: Int]()
        for (phoneNumber, contactRef) in fetchedSystemContacts.phoneNumberToContactRef {
            guard let signalRecipient = discoverableRecipient(for: phoneNumber, tx: transaction) else {
                // Not discoverable.
                continue
            }
            guard let serviceId = signalRecipient.aci ?? signalRecipient.pni else {
                owsFailDebug("Can't be discoverable without an ACI or PNI.")
                continue
            }
            discoverableRecipients[phoneNumber] = (signalRecipient, serviceId)
            discoverablePhoneNumberCounts[contactRef.cnContactId, default: 0] += 1
        }
        var signalAccounts = [SignalAccount]()
        for (phoneNumber, contactRef) in fetchedSystemContacts.phoneNumberToContactRef {
            guard let (signalRecipient, serviceId) = discoverableRecipients[phoneNumber] else {
                continue
            }
            guard let discoverablePhoneNumberCount = discoverablePhoneNumberCounts[contactRef.cnContactId] else {
                owsFailDebug("Couldn't find relatedPhoneNumbers")
                continue
            }
            guard let systemContact = fetchedSystemContacts.cnContactIdToContact[contactRef.cnContactId] else {
                owsFailDebug("Couldn't find systemContact")
                continue
            }
            let multipleAccountLabelText = Contact.uniquePhoneNumberLabel(
                userProvidedLabel: contactRef.userProvidedLabel,
                discoverablePhoneNumberCount: discoverablePhoneNumberCount
            )
            let contactAvatarHash = buildContactAvatarHash(for: systemContact)
            let signalAccount = SignalAccount(
                recipientPhoneNumber: signalRecipient.phoneNumber?.stringValue,
                recipientServiceId: serviceId,
                multipleAccountLabelText: multipleAccountLabelText,
                cnContactId: systemContact.cnContactId,
                givenName: systemContact.firstName,
                familyName: systemContact.lastName,
                nickname: systemContact.nickname,
                fullName: systemContact.fullName,
                contactAvatarHash: contactAvatarHash
            )
            signalAccounts.append(signalAccount)
        }
        return signalAccounts
    }

    private func buildSignalAccountsAndUpdatePersistedState(for fetchedSystemContacts: FetchedSystemContacts) {
        assertOnQueue(intersectionQueue)

        let (oldSignalAccounts, newSignalAccounts) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let oldSignalAccounts = SignalAccount.anyFetchAll(transaction: transaction)
            let newSignalAccounts = buildSignalAccounts(for: fetchedSystemContacts, transaction: transaction)
            return (oldSignalAccounts, newSignalAccounts)
        }
        let oldSignalAccountsMap: [String?: SignalAccount] = Dictionary(
            oldSignalAccounts.lazy.map { ($0.recipientPhoneNumber, $0) },
            uniquingKeysWith: { _, new in new }
        )
        var newSignalAccountsMap = [String: SignalAccount]()

        var signalAccountChanges: [(remove: SignalAccount?, insert: SignalAccount?)] = []
        for newSignalAccount in newSignalAccounts {
            guard let phoneNumber = newSignalAccount.recipientPhoneNumber else {
                owsFailDebug("Can't have a system contact without a phone number.")
                continue
            }

            // The user might have multiple entries in their address book with the same phone number.
            if newSignalAccountsMap[phoneNumber] != nil {
                Logger.warn("Ignoring redundant signal account")
                continue
            }

            let oldSignalAccountToKeep: SignalAccount?
            let oldSignalAccount = oldSignalAccountsMap[phoneNumber]
            switch oldSignalAccount {
            case .none:
                oldSignalAccountToKeep = nil

            case .some(let oldSignalAccount) where oldSignalAccount.hasSameContent(newSignalAccount) && !oldSignalAccount.hasDeprecatedRepresentation:
                // Same content, no need to update.
                oldSignalAccountToKeep = oldSignalAccount

            case .some:
                oldSignalAccountToKeep = nil
            }

            if let oldSignalAccount = oldSignalAccountToKeep {
                newSignalAccountsMap[phoneNumber] = oldSignalAccount
            } else {
                newSignalAccountsMap[phoneNumber] = newSignalAccount
                signalAccountChanges.append((oldSignalAccount, newSignalAccount))
            }
        }

        // Clean up orphans.
        for signalAccount in oldSignalAccounts {
            if let phoneNumber = signalAccount.recipientPhoneNumber, newSignalAccountsMap[phoneNumber]?.uniqueId == signalAccount.uniqueId {
                // Don't clean up SignalAccounts that aren't changing.
                continue
            }
            // Clean up instances that have been replaced by another instance or are no
            // longer in the system contacts.
            signalAccountChanges.append((signalAccount, nil))
        }

        // Update cached SignalAccounts on disk
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            for (signalAccountToRemove, signalAccountToInsert) in signalAccountChanges {
                let oldSignalAccount = signalAccountToRemove.flatMap {
                    SignalAccount.anyFetch(uniqueId: $0.uniqueId, transaction: tx)
                }
                let newSignalAccount = signalAccountToInsert

                oldSignalAccount?.anyRemove(transaction: tx)
                newSignalAccount?.anyInsert(transaction: tx)

                updatePhoneNumberVisibilityIfNeeded(
                    oldSignalAccount: oldSignalAccount,
                    newSignalAccount: newSignalAccount,
                    tx: tx.asV2Write
                )
            }

            if !signalAccountChanges.isEmpty {
                Logger.info("Updated \(signalAccountChanges.count) SignalAccounts; now have \(newSignalAccountsMap.count) total")
            }

            // Add system contacts to the profile whitelist immediately so that they do
            // not see the "message request" UI.
            SSKEnvironment.shared.profileManagerRef.addUsers(
                toProfileWhitelist: newSignalAccountsMap.values.map { $0.recipientAddress },
                userProfileWriter: .systemContactsFetch,
                transaction: tx
            )
        }

        // Once we've persisted new SignalAccount state, we should let
        // StorageService know.
        updateStorageServiceForSystemContactsFetch(
            allSignalAccountsBeforeFetch: oldSignalAccountsMap,
            allSignalAccountsAfterFetch: newSignalAccountsMap
        )

        let didChangeAnySignalAccount = !signalAccountChanges.isEmpty
        DispatchQueue.main.async {
            // Post a notification if something changed or this is the first load since launch.
            let shouldNotify = didChangeAnySignalAccount || !self.hasLoadedSystemContacts
            self.hasLoadedSystemContacts = true
            self.didUpdateSignalAccounts(shouldNotify: shouldNotify)
        }
    }

    /// Updates StorageService records for any Signal contacts associated with
    /// a system contact that has been added, removed, or modified in a
    /// relevant way. Has no effect when we are a linked device.
    private func updateStorageServiceForSystemContactsFetch(
        allSignalAccountsBeforeFetch: [String?: SignalAccount],
        allSignalAccountsAfterFetch: [String: SignalAccount]
    ) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false else {
            return
        }

        var phoneNumbersToUpdateInStorageService = [String]()

        var allSignalAccountsBeforeFetch = allSignalAccountsBeforeFetch
        for (phoneNumber, newSignalAccount) in allSignalAccountsAfterFetch {
            let oldSignalAccount = allSignalAccountsBeforeFetch.removeValue(forKey: phoneNumber)
            if let oldSignalAccount, newSignalAccount.hasSameName(oldSignalAccount) {
                // No Storage Service-relevant changes were made.
                continue
            }
            phoneNumbersToUpdateInStorageService.append(phoneNumber)
        }
        // Anything left in ...BeforeFetch was removed.
        phoneNumbersToUpdateInStorageService.append(
            contentsOf: allSignalAccountsBeforeFetch.keys.lazy.compactMap { $0 }
        )

        let updatedRecipientUniqueIds = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return phoneNumbersToUpdateInStorageService.compactMap {
                let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
                return recipientDatabaseTable.fetchRecipient(phoneNumber: $0, transaction: tx.asV2Read)?.uniqueId
            }
        }

        SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedRecipientUniqueIds: updatedRecipientUniqueIds)
    }

    private func updatePhoneNumberVisibilityIfNeeded(
        oldSignalAccount: SignalAccount?,
        newSignalAccount: SignalAccount?,
        tx: DBWriteTransaction
    ) {
        let aciToUpdate = SignalAccount.aciForPhoneNumberVisibilityUpdate(
            oldAccount: oldSignalAccount,
            newAccount: newSignalAccount
        )
        guard let aciToUpdate else {
            return
        }
        let recipient = recipientDatabaseTable.fetchRecipient(serviceId: aciToUpdate, transaction: tx)
        guard let recipient else {
            return
        }
        // Tell the cache to refresh its state for this recipient. It will check
        // whether or not the number should be visible based on this state and the
        // state of system contacts.
        SSKEnvironment.shared.signalServiceAddressCacheRef.updateRecipient(recipient, tx: tx)
    }

    public func didUpdateSignalAccounts(transaction: SDSAnyWriteTransaction) {
        transaction.addTransactionFinalizationBlock(forKey: "OWSContactsManager.didUpdateSignalAccounts") { _ in
            self.didUpdateSignalAccounts(shouldNotify: true)
        }
    }

    private func didUpdateSignalAccounts(shouldNotify: Bool) {
        if shouldNotify {
            NotificationCenter.default.postNotificationNameAsync(.OWSContactsManagerSignalAccountsDidChange, object: nil)
        }
    }

    private enum Constants {
        static let nextFullIntersectionDate = "OWSContactsManagerKeyNextFullIntersectionDate2"
        static let lastKnownContactPhoneNumbers = "OWSContactsManagerKeyLastKnownContactPhoneNumbers"
        static let didIntersectAddressBook = "didIntersectAddressBook"
    }

    func updateContacts(_ addressBookContacts: [SystemContact]?, isUserRequested: Bool) {
        intersectionQueue.async { self._updateContacts(addressBookContacts, isUserRequested: isUserRequested) }
    }

    private func fetchPriorIntersectionPhoneNumbers(tx: SDSAnyReadTransaction) -> Set<String>? {
        return keyValueStore.getSet(Constants.lastKnownContactPhoneNumbers, ofClass: NSString.self, transaction: tx.asV2Read) as Set<String>?
    }

    private func setPriorIntersectionPhoneNumbers(_ phoneNumbers: Set<String>, tx: SDSAnyWriteTransaction) {
        keyValueStore.setObject(phoneNumbers, key: Constants.lastKnownContactPhoneNumbers, transaction: tx.asV2Write)
    }

    private enum IntersectionMode {
        /// It's time for the regularly-scheduled full intersection.
        case fullIntersection

        /// It's not time for the regularly-scheduled full intersection. Only check
        /// new phone numbers.
        case deltaIntersection(priorPhoneNumbers: Set<String>)
    }

    private func fetchIntersectionMode(isUserRequested: Bool, tx: SDSAnyReadTransaction) -> IntersectionMode {
        if isUserRequested {
            return .fullIntersection
        }
        let nextFullIntersectionDate = keyValueStore.getDate(Constants.nextFullIntersectionDate, transaction: tx.asV2Read)
        guard let nextFullIntersectionDate, nextFullIntersectionDate.isAfterNow else {
            return .fullIntersection
        }
        guard let priorPhoneNumbers = fetchPriorIntersectionPhoneNumbers(tx: tx) else {
            // We don't know the prior phone numbers, so do a `.fullIntersection`.
            return .fullIntersection
        }
        return .deltaIntersection(priorPhoneNumbers: priorPhoneNumbers)
    }

    private func _updateContacts(_ addressBookContacts: [SystemContact]?, isUserRequested: Bool) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localNumber = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
        let fetchedSystemContacts = FetchedSystemContacts.parseContacts(
            addressBookContacts ?? [],
            phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef,
            localPhoneNumber: localNumber
        )
        setFetchedSystemContacts(fetchedSystemContacts)

        intersectContacts(
            fetchedSystemContacts: fetchedSystemContacts,
            localNumber: localNumber,
            isUserRequested: isUserRequested
        )
    }

    private func intersectContacts(
        fetchedSystemContacts: FetchedSystemContacts,
        localNumber: String?,
        isUserRequested: Bool
    ) {
        let systemContactPhoneNumbers = fetchedSystemContacts.phoneNumberToContactRef.keys

        let (intersectionMode, signalRecipientPhoneNumbers) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let intersectionMode = fetchIntersectionMode(isUserRequested: isUserRequested, tx: tx)
            let signalRecipientPhoneNumbers = SignalRecipient.fetchAllPhoneNumbers(tx: tx)
            return (intersectionMode, signalRecipientPhoneNumbers)
        }

        var phoneNumbersToIntersect = Set(signalRecipientPhoneNumbers.keys)
        phoneNumbersToIntersect.formUnion(systemContactPhoneNumbers.lazy.map { $0.rawValue.stringValue })
        phoneNumbersToIntersect.formUnion(systemContactPhoneNumbers.lazy.flatMap { $0.alternatePhoneNumbers().map { $0.stringValue } })
        if case .deltaIntersection(let priorPhoneNumbers) = intersectionMode {
            phoneNumbersToIntersect.subtract(priorPhoneNumbers)
        }
        if let localNumber {
            phoneNumbersToIntersect.remove(localNumber)
        }

        switch intersectionMode {
        case .fullIntersection:
            Logger.info("Performing full intersection for \(phoneNumbersToIntersect.count) phone numbers.")
        case .deltaIntersection:
            Logger.info("Performing delta intersection for \(phoneNumbersToIntersect.count) phone numbers.")
        }

        let intersectionPromise = Promise.wrapAsync {
            return try await self.intersectContacts(phoneNumbersToIntersect)
        }
        intersectionPromise.done(on: intersectionQueue) { intersectedRecipients in
            // Mark it as complete. If the app crashes after this transaction, we'll
            // avoid a redundant (expensive) intersection when we retry.
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.didFinishIntersection(
                    mode: intersectionMode,
                    phoneNumbers: phoneNumbersToIntersect,
                    tx: tx
                )
            }

            // Save names to the database before generating notifications.
            self.buildSignalAccountsAndUpdatePersistedState(for: fetchedSystemContacts)

            try SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.postJoinNotificationsIfNeeded(
                    addressBookPhoneNumbers: systemContactPhoneNumbers,
                    phoneNumberRegistrationStatus: signalRecipientPhoneNumbers,
                    intersectedRecipients: intersectedRecipients,
                    tx: tx
                )
                try self.unhideRecipientsIfNeeded(
                    addressBookPhoneNumbers: systemContactPhoneNumbers,
                    tx: tx.asV2Write
                )
            }
        }.catch(on: intersectionQueue) { error in
            owsFailDebug("Couldn't intersect contacts: \(error)")
        }
    }

    private func postJoinNotificationsIfNeeded(
        addressBookPhoneNumbers: some Sequence<CanonicalPhoneNumber>,
        phoneNumberRegistrationStatus: [String: Bool],
        intersectedRecipients: some Sequence<SignalRecipient>,
        tx: SDSAnyWriteTransaction
    ) {
        let didIntersectAtLeastOnce = keyValueStore.getBool(Constants.didIntersectAddressBook, defaultValue: false, transaction: tx.asV2Read)
        guard didIntersectAtLeastOnce else {
            // This is the first address book intersection. Don't post notifications,
            // but mark the flag so that we post notifications next time.
            keyValueStore.setBool(true, key: Constants.didIntersectAddressBook, transaction: tx.asV2Write)
            return
        }
        guard SSKEnvironment.shared.preferencesRef.shouldNotifyOfNewAccounts(transaction: tx) else {
            return
        }
        let phoneNumbers = Set(addressBookPhoneNumbers.lazy.map { $0.rawValue.stringValue })
        for signalRecipient in intersectedRecipients {
            guard let phoneNumber = signalRecipient.phoneNumber, phoneNumber.isDiscoverable else {
                continue  // Can't happen.
            }
            guard phoneNumbers.contains(phoneNumber.stringValue) else {
                continue  // Not in the address book -- no notification.
            }
            guard phoneNumberRegistrationStatus[phoneNumber.stringValue] != true else {
                continue  // They were already registered -- no notification.
            }
            NewAccountDiscovery.postNotification(for: signalRecipient, tx: tx)
        }
    }

    /// We cannot hide a contact that is in our address book.
    /// As a result, when a contact that was hidden is added to the address book,
    /// we must unhide them.
    private func unhideRecipientsIfNeeded(
        addressBookPhoneNumbers: some Sequence<CanonicalPhoneNumber>,
        tx: DBWriteTransaction
    ) throws {
        let recipientHidingManager = DependenciesBridge.shared.recipientHidingManager
        let phoneNumbers = Set(addressBookPhoneNumbers.lazy.map { $0.rawValue.stringValue })
        for hiddenRecipient in recipientHidingManager.hiddenRecipients(tx: tx) {
            guard let phoneNumber = hiddenRecipient.phoneNumber else {
                continue // We can't unhide because of the address book w/o a phone number.
            }
            guard phoneNumber.isDiscoverable else {
                continue // Not discoverable -- no unhiding.
            }
            guard phoneNumbers.contains(phoneNumber.stringValue) else {
                continue  // Not in the address book -- no unhiding.
            }
            try DependenciesBridge.shared.recipientHidingManager.removeHiddenRecipient(
                hiddenRecipient,
                wasLocallyInitiated: true,
                tx: tx
            )
        }
    }

    private func didFinishIntersection(
        mode intersectionMode: IntersectionMode,
        phoneNumbers: Set<String>,
        tx: SDSAnyWriteTransaction
    ) {
        switch intersectionMode {
        case .fullIntersection:
            setPriorIntersectionPhoneNumbers(phoneNumbers, tx: tx)
            let nextFullIntersectionDate = Date(timeIntervalSinceNow: RemoteConfig.current.cdsSyncInterval)
            keyValueStore.setDate(nextFullIntersectionDate, key: Constants.nextFullIntersectionDate, transaction: tx.asV2Write)

        case .deltaIntersection:
            // If a user has a "flaky" address book (perhaps it's a network-linked
            // directory that goes in and out of existence), we could get thrashing
            // between what the last known set is, causing us to re-intersect contacts
            // many times within the debounce interval. So while we're doing
            // incremental intersections, we *accumulate*, rather than replace, the set
            // of recently intersected contacts.
            let priorPhoneNumbers = fetchPriorIntersectionPhoneNumbers(tx: tx) ?? []
            setPriorIntersectionPhoneNumbers(priorPhoneNumbers.union(phoneNumbers), tx: tx)
        }
    }

    private func intersectContacts(_ phoneNumbers: Set<String>) async throws -> Set<SignalRecipient> {
        if phoneNumbers.isEmpty {
            return []
        }
        return try await Retry.performRepeatedly(
            block: {
                return try await SSKEnvironment.shared.contactDiscoveryManagerRef.lookUp(
                    phoneNumbers: phoneNumbers,
                    mode: .contactIntersection
                )
            },
            onError: { error, attemptCount in
                if case ContactDiscoveryError.rateLimit(retryAfter: _) = error {
                    Logger.error("Contact intersection hit rate limit with error: \(error)")
                    throw error
                }

                if error is ContactDiscoveryError, !error.isRetryable {
                    Logger.error("Contact intersection error suggests not to retry. Aborting without rescheduling.")
                    throw error
                }

                // TODO: Abort if another contact intersection succeeds in the meantime.
                Logger.warn("Contact intersection failed with error: \(error). Rescheduling.")
                try await Task.sleep(nanoseconds: OWSOperation.retryIntervalForExponentialBackoffNs(failureCount: attemptCount, maxBackoff: .infinity))
            }
        )
    }

    private static let unknownAddressFetchDateMap = AtomicDictionary<Aci, Date>(lock: .sharedGlobal)

    @objc(fetchProfileForUnknownAddress:)
    func fetchProfile(forUnknownAddress address: SignalServiceAddress) {
        // We only consider ACIs b/c PNIs will never give us a name other than "Unknown".
        guard let aci = address.serviceId as? Aci else {
            return
        }
        let minFetchInterval = kMinuteInterval * 30
        if
            let lastFetchDate = Self.unknownAddressFetchDateMap[aci],
            abs(lastFetchDate.timeIntervalSinceNow) < minFetchInterval
        {
            return
        }

        Self.unknownAddressFetchDateMap[aci] = Date()

        let profileFetcher = SSKEnvironment.shared.profileFetcherRef
        _ = profileFetcher.fetchProfileSync(for: aci, options: [.opportunistic])
    }

    // MARK: - System Contacts

    private func setFetchedSystemContacts(_ fetchedSystemContacts: FetchedSystemContacts) {
        systemContactsCache.fetchedSystemContacts.set(fetchedSystemContacts)
        cnContactCache.removeAllObjects()
        NotificationCenter.default.postNotificationNameAsync(.OWSContactsManagerContactsDidChange, object: nil)
    }

    public func cnContact(withId cnContactId: String?) -> CNContact? {
        guard let cnContactId else {
            return nil
        }
        if let cnContact = cnContactCache[cnContactId] {
            return cnContact
        }
        let cnContact = systemContactsFetcher.fetchCNContact(contactId: cnContactId)
        if let cnContact {
            cnContactCache[cnContactId] = cnContact
        }
        return cnContact
    }

    public func cnContactId(for phoneNumber: String) -> String? {
        guard let phoneNumber = E164(phoneNumber) else {
            return nil
        }
        let fetchedSystemContacts = systemContactsCache.fetchedSystemContacts.get()
        let canonicalPhoneNumber = CanonicalPhoneNumber(nonCanonicalPhoneNumber: phoneNumber)
        return fetchedSystemContacts?.phoneNumberToContactRef[canonicalPhoneNumber]?.cnContactId
    }

    // MARK: - Display Names

    private func displayNamesRefinery(
        for addresses: [SignalServiceAddress],
        transaction: SDSAnyReadTransaction
    ) -> Refinery<SignalServiceAddress, DisplayName> {
        let tx = transaction.asV2Read
        return .init(addresses).refine { addresses -> [DisplayName?] in
            return addresses.map { address -> DisplayName? in
                recipientDatabaseTable.fetchRecipient(address: address, tx: tx)
                    .flatMap { nicknameManager.fetchNickname(for: $0, tx: tx) }
                    .flatMap(ProfileName.init(nicknameRecord:))
                    .map(DisplayName.nickname(_:))
            }
        }.refine { addresses -> [DisplayName?] in
            // Prefer a saved name from system contacts, if available.
            return systemContactNames(for: addresses, tx: transaction)
                .map { $0.map { .systemContactName($0) } }
        }.refine { addresses -> [DisplayName?] in
            return SSKEnvironment.shared.profileManagerRef.fetchUserProfiles(for: Array(addresses), tx: transaction)
                .map { $0?.nameComponents.map { .profileName($0) } }
        }.refine { addresses -> [DisplayName?] in
            return addresses.map { $0.e164.map { .phoneNumber($0) } }
        }.refine { addresses -> [DisplayName?] in
            return usernameLookupManager.fetchUsernames(
                forAddresses: addresses,
                transaction: transaction.asV2Read
            ).map { $0.map { .username($0) } }
        }.refine { addresses in
            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            return addresses.lazy.map { address -> DisplayName in
                let signalRecipient = recipientDatabaseTable.fetchRecipient(
                    address: address,
                    tx: transaction.asV2Read
                )
                if let signalRecipient, !signalRecipient.isRegistered {
                    return .deletedAccount
                } else {
                    self.fetchProfile(forUnknownAddress: address)
                    return .unknown
                }
            } as [DisplayName?]
        }
    }

    public func displayNamesByAddress(
        for addresses: [SignalServiceAddress],
        transaction: SDSAnyReadTransaction
    ) -> [SignalServiceAddress: DisplayName] {
        Dictionary(displayNamesRefinery(for: addresses, transaction: transaction))
    }

    public func displayNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [DisplayName] {
        displayNamesRefinery(for: addresses, transaction: tx).values.map { $0! }
    }

    private func systemContactNames(for addresses: some Sequence<SignalServiceAddress>, tx: SDSAnyReadTransaction) -> [DisplayName.SystemContactName?] {
        let phoneNumbers = addresses.map { $0.phoneNumber }
        var compactedResult = systemContactNames(for: phoneNumbers.compacted(), tx: tx).makeIterator()
        return phoneNumbers.map { $0 != nil ? compactedResult.next()! : nil }
    }

    public func fetchSignalAccounts(
        for phoneNumbers: [String],
        transaction: SDSAnyReadTransaction
    ) -> [SignalAccount?] {
        return SignalAccountFinder().signalAccounts(for: phoneNumbers, tx: transaction)
    }

    public func shortestDisplayName(
        forGroupMember groupMember: SignalServiceAddress,
        inGroup groupModel: TSGroupModel,
        transaction: SDSAnyReadTransaction
    ) -> String {
        let displayName = self.displayName(for: groupMember, tx: transaction)
        let fullName = displayName.resolvedValue()
        let shortName = displayName.resolvedValue(useShortNameIfAvailable: true)
        guard fullName != shortName else {
            return fullName
        }

        // Try to return just the short name unless the group contains another
        // member with the same short name.

        for otherMember in groupModel.groupMembership.fullMembers {
            guard otherMember != groupMember else { continue }

            // Use the full name if the member's short name matches
            // another member's full or short name.
            let otherDisplayName = self.displayName(for: otherMember, tx: transaction)
            guard otherDisplayName.resolvedValue() != shortName else { return fullName }
            guard otherDisplayName.resolvedValue(useShortNameIfAvailable: true) != shortName else { return fullName }
        }

        return shortName
    }
}

// MARK: - ContactManager

extension ContactManager {
    public func nameForAddress(
        _ address: SignalServiceAddress,
        localUserDisplayMode: LocalUserDisplayMode,
        short: Bool,
        transaction: SDSAnyReadTransaction
    ) -> NSAttributedString {
        return { () -> String in
            if address.isLocalAddress {
                switch localUserDisplayMode {
                case .noteToSelf:
                    return MessageStrings.noteToSelf
                case .asLocalUser:
                    return CommonStrings.you
                case .asUser:
                    break
                }
            }
            let displayName = self.displayName(for: address, tx: transaction)
            return displayName.resolvedValue(useShortNameIfAvailable: short)
        }().asAttributedString
    }

    public func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        return displayName(for: thread, tx: transaction)?.resolvedValue() ?? ""
    }

    public func displayName(for thread: TSThread, tx: SDSAnyReadTransaction) -> ThreadDisplayName? {
        if thread.isNoteToSelf {
            return .noteToSelf
        }
        switch thread {
        case let thread as TSContactThread:
            return .contactThread(displayName(for: thread.contactAddress, tx: tx))
        case let thread as TSGroupThread:
            return .groupThread(thread.groupNameOrDefault)
        default:
            owsFailDebug("Unexpected thread type: \(type(of: thread))")
            return nil
        }
    }

    public func sortSignalServiceAddresses(
        _ addresses: some Sequence<SignalServiceAddress>,
        transaction: SDSAnyReadTransaction
    ) -> [SignalServiceAddress] {
        return sortedComparableNames(for: addresses, tx: transaction).map { $0.address }
    }

    public func sortedComparableNames(
        for addresses: some Sequence<SignalServiceAddress>,
        tx: SDSAnyReadTransaction
    ) -> [ComparableDisplayName] {
        let addresses = Array(addresses)
        let displayNames = self.displayNames(for: addresses, tx: tx)
        let config = DisplayName.ComparableValue.Config.current()
        return zip(addresses, displayNames).map { (address, displayName) in
            return ComparableDisplayName(
                address: address,
                displayName: displayName,
                config: config
            )
        }.sorted(by: <)
    }
}

// MARK: - ThreadDisplayName

public enum ThreadDisplayName {
    case noteToSelf
    case contactThread(DisplayName)
    case groupThread(String)

    public func resolvedValue() -> String {
        switch self {
        case .noteToSelf:
            return MessageStrings.noteToSelf
        case .contactThread(let displayName):
            return displayName.resolvedValue()
        case .groupThread(let groupName):
            return groupName
        }
    }
}
