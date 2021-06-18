//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

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
        if nil == groupThread.groupModel.groupAvatarData {
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
            owsFailDebug("Missung uuid for user.")
            return
        }
        Self.skipContactAvatarBlurByUuidStore.setBool(true,
                                                      key: uuid.uuidString,
                                                      transaction: transaction)
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
        Self.skipGroupAvatarBlurByGroupIdStore.setBool(true,
                                                       key: groupId.hexadecimalString,
                                                       transaction: transaction)
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
            return try image.withGausianBlur(radius: 16,
                                             resizeToMaxPixelDimension: 100)
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

        if let phoneNumber = self.phoneNumber(for: address, transaction: transaction),
           let contact = self.allContactsMap[phoneNumber],
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

            if let contactAvatarJpegData = signalAccount.contactAvatarJpegData,
               let validData = validateIfNecessary(contactAvatarJpegData) {
                return validData
            }
        }
        return nil
    }
}
