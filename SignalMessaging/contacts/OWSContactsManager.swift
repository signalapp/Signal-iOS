//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

fileprivate extension OWSContactsManager {
    static let skipContactAvatarBlurByUuidStore = SDSKeyValueStore(collection: "OWSContactsManager.skipContactAvatarBlurByUuidStore")
    static let skipGroupAvatarBlurByGroupIdStore = SDSKeyValueStore(collection: "OWSContactsManager.skipGroupAvatarBlurByGroupIdStore")

    static var unblurredAvatarContactCache = AtomicSet<UUID>()
    static var unblurredAvatarGroupCache = AtomicSet<Data>()
}

// MARK: -

@objc
public extension OWSContactsManager {

    // MARK: - Avatar Cache

    private static let unfairLock = UnfairLock()

    func getImageFromAvatarCache(key: String, diameter: CGFloat) -> UIImage? {
        Self.unfairLock.withLock {
            self.avatarCachePrivate.image(forKey: key as NSString, diameter: diameter)
        }
    }

    func setImageForAvatarCache(_ image: UIImage, forKey key: String, diameter: CGFloat) {
        Self.unfairLock.withLock {
            self.avatarCachePrivate.setImage(image, forKey: key as NSString, diameter: diameter)
        }
    }

    func removeAllFromAvatarCacheWithKey(_ key: String) {
        Self.unfairLock.withLock {
            self.avatarCachePrivate.removeAllImages(forKey: key as NSString)
        }
    }

    func removeAllFromAvatarCache() {
        Self.unfairLock.withLock {
            self.avatarCachePrivate.removeAllImages()
        }
    }

    // MARK: - Avatar Blurring

    func shouldBlurAvatar(thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return shouldBlurContactAvatar(contactThread: contactThread, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return shouldBlurGroupAvatar(groupThread: groupThread, transaction: transaction)
        } else {
            owsFailDebug("Invalid thread.")
            return false
        }
    }

    func shouldBlurContactAvatar(address: SignalServiceAddress,
                                 transaction: SDSAnyReadTransaction) -> Bool {
        func cacheContains() -> Bool {
            guard let uuid = address.uuid else {
                return false
            }
            return Self.unblurredAvatarContactCache.contains(uuid)
        }
        func addToCache() {
            guard let uuid = address.uuid else {
                return
            }
            Self.unblurredAvatarContactCache.insert(uuid)
        }
        if cacheContains() {
            return false
        }
        guard let contactThread = TSContactThread.getWithContactAddress(address,
                                                                        transaction: transaction) else {
            addToCache()
            return false
        }
        return shouldBlurContactAvatar(contactThread: contactThread, transaction: transaction)
    }

    func shouldBlurContactAvatar(contactThread: TSContactThread,
                                 transaction: SDSAnyReadTransaction) -> Bool {
        let address = contactThread.contactAddress
        func cacheContains() -> Bool {
            guard let uuid = address.uuid else {
                return false
            }
            return Self.unblurredAvatarContactCache.contains(uuid)
        }
        func addToCache() {
            guard let uuid = address.uuid else {
                return
            }
            Self.unblurredAvatarContactCache.insert(uuid)
        }
        if cacheContains() {
            return false
        }
        if !contactThread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) {
            addToCache()
            return false
        }
        // ...and not in a whitelisted group with the locar user.
        if isInWhitelistedGroupWithLocalUser(address: address,
                                             transaction: transaction) {
            addToCache()
            return false
        }
        // We can skip avatar blurring if the user has explicitly waived the blurring.
        if let uuid = address.uuid,
           Self.skipContactAvatarBlurByUuidStore.getBool(uuid.uuidString,
                                                         defaultValue: false,
                                                         transaction: transaction) {
            addToCache()
            return false
        }
        return true
    }

    func shouldBlurGroupAvatar(groupThread: TSGroupThread,
                               transaction: SDSAnyReadTransaction) -> Bool {
        let groupId = groupThread.groupId
        func cacheContains() -> Bool {
            Self.unblurredAvatarGroupCache.contains(groupId)
        }
        func addToCache() {
            Self.unblurredAvatarGroupCache.insert(groupId)
        }
        if cacheContains() {
            return false
        }
        if nil == groupThread.groupModel.groupAvatarData {
            // DO NOT add to the cache.
            return false
        }
        if !groupThread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) {
            addToCache()
            return false
        }
        // We can skip avatar blurring if the user has explicitly waived the blurring.
        if Self.skipGroupAvatarBlurByGroupIdStore.getBool(groupId.hexadecimalString,
                                                          defaultValue: false,
                                                          transaction: transaction) {
            addToCache()
            return false
        }
        return true
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
        NotificationCenter.default.postNotificationNameAsync(Self.skipContactAvatarBlurDidChange,
                                                             object: nil,
                                                             userInfo: [
                                                                Self.skipContactAvatarBlurAddressKey: address
                                                             ])
    }

    func doNotBlurGroupAvatar(groupThread: TSGroupThread,
                              transaction: SDSAnyWriteTransaction) {

        let groupId = groupThread.groupId
        let groupUniqueId = groupThread.uniqueId
        Self.skipGroupAvatarBlurByGroupIdStore.setBool(true,
                                                       key: groupId.hexadecimalString,
                                                       transaction: transaction)
        NotificationCenter.default.postNotificationNameAsync(Self.skipGroupAvatarBlurDidChange,
                                                             object: nil,
                                                             userInfo: [
                                                                Self.skipGroupAvatarBlurGroupUniqueIdKey: groupUniqueId
                                                             ])
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

    // MARK: - Shared Groups

    func isInWhitelistedGroupWithLocalUser(address otherAddress: SignalServiceAddress,
                                           transaction: SDSAnyReadTransaction) -> Bool {
        let otherGroupThreadIds = TSGroupThread.groupThreadIds(with: otherAddress, transaction: transaction)
        guard !otherGroupThreadIds.isEmpty else {
            return false
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
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
