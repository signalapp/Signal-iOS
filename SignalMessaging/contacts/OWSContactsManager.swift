//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSContactsManager {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

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

    // MARK: -

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
