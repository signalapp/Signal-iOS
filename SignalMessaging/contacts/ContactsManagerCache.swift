//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public protocol ContactsManagerCache: AnyObject {
    func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount]

    // Order respects the systems contact sorting preference.
    func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount]

    func setSortedSignalAccounts(_ signalAccounts: [SignalAccount])

    func contact(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact?

    func allContacts(transaction: SDSAnyReadTransaction) -> [Contact]

    func contactsMaps(transaction: SDSAnyReadTransaction) -> ContactsMaps

    func setContactsMaps(_ contactsMaps: ContactsMaps,
                         localNumber: String?,
                         transaction: SDSAnyWriteTransaction)

    func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsManagerCacheSummary
}

// MARK: -

@objc
public class ContactsManagerCacheSummary: NSObject {
    @objc
    public let contactCount: UInt
    @objc
    public let signalAccountCount: UInt

    required init(contactCount: UInt, signalAccountCount: UInt) {
        self.contactCount = contactCount
        self.signalAccountCount = signalAccountCount
    }
}

// MARK: -

@objc
public class ContactsMaps: NSObject {
    @objc
    public let uniqueIdToContactMap: [String: Contact]
    @objc
    public let phoneNumberToContactMap: [String: Contact]

    @objc
    public var allContacts: [Contact] { Array(uniqueIdToContactMap.values) }

    required init(uniqueIdToContactMap: [String: Contact],
                  phoneNumberToContactMap: [String: Contact]) {
        self.uniqueIdToContactMap = uniqueIdToContactMap
        self.phoneNumberToContactMap = phoneNumberToContactMap
    }

    static let empty: ContactsMaps = ContactsMaps(uniqueIdToContactMap: [:], phoneNumberToContactMap: [:])

    // Builds a map of phone number-to-Contact.
    // A given Contact may have multiple phone numbers.
    @objc
    public static func build(contacts: [Contact],
                             localNumber: String?) -> ContactsMaps {

        var uniqueIdToContactMap = [String: Contact]()
        var phoneNumberToContactMap = [String: Contact]()
        for contact in contacts {
            let phoneNumbers = Self.phoneNumbers(forContact: contact, localNumber: localNumber)
            guard !phoneNumbers.isEmpty else {
                continue
            }

            uniqueIdToContactMap[contact.uniqueId] = contact

            for phoneNumber in phoneNumbers {
                phoneNumberToContactMap[phoneNumber] = contact
            }
        }
        return ContactsMaps(uniqueIdToContactMap: uniqueIdToContactMap,
                            phoneNumberToContactMap: phoneNumberToContactMap)
    }

    fileprivate static func phoneNumbers(forContact contact: Contact, localNumber: String?) -> [String] {
        let phoneNumbers: [String] = contact.parsedPhoneNumbers.compactMap { phoneNumber in
            guard let phoneNumberE164 = phoneNumber.toE164().nilIfEmpty else {
                return nil
            }

            return phoneNumberE164
        }

        if let localNumber = localNumber, phoneNumbers.contains(localNumber) {
            // Ignore any system contact records for the local contact.
            // For the local user we never want to show the avatar /
            // name that you have entered for yourself in your system
            // contacts. Instead, we always want to display your profile
            // name and avatar.
            return []
        }

        return phoneNumbers
    }

    @objc
    public func isSystemContact(address: SignalServiceAddress) -> Bool {
        guard let phoneNumber = address.phoneNumber?.nilIfEmpty else {
            return false
        }
        return isSystemContact(phoneNumber: phoneNumber)
    }

    @objc
    public func isSystemContact(phoneNumber: String) -> Bool {
        phoneNumberToContactMap[phoneNumber] != nil
    }

    public func isEqualForCache(_ other: ContactsMaps) -> Bool {
        let mapSelf = self.uniqueIdToContactMap
        let mapOther = other.uniqueIdToContactMap
        let keysSelf = Set(mapSelf.keys)
        let keysOther = Set(mapOther.keys)
        guard keysSelf == keysOther else {
            return false
        }
        for key in keysSelf {
            guard let valueSelf = mapSelf[key],
                  let valueOther = mapOther[key],
                  valueSelf.isEqualForCache(valueOther) else {
                      return false
                  }
        }
        return true
    }
}

// MARK: -

@objc
public class ContactsManagerCacheInDatabase: NSObject, ContactsManagerCache {
    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        SignalAccount.anyFetchAll(transaction: transaction)
    }

    // Order respects the systems contact sorting preference.
    @objc
    public func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        contactsManagerImpl.sortSignalAccounts(unsortedSignalAccounts(transaction: transaction),
                                               transaction: transaction)
    }

    @objc
    public func setSortedSignalAccounts(_ signalAccounts: [SignalAccount]) {
        // Ignore.
    }

    private static let uniqueIdStore = SDSKeyValueStore(collection: "ContactsManagerCache.uniqueIdStore")
    private static let phoneNumberStore = SDSKeyValueStore(collection: "ContactsManagerCache.phoneNumberStore")

    private static func serializeContact(_ contact: Contact, label: String) -> Data? {
        let data = NSKeyedArchiver.archivedData(withRootObject: contact)
        guard !data.isEmpty else {
            owsFailDebug("Could not serialize contact: \(label).")
            return nil
        }
        return data
    }

    private static func deserializeContact(data: Data, label: String) -> Contact? {
        do {
            guard let contact = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Contact else {
                owsFailDebug("Invalid value: \(label).")
                return nil
            }
            return contact
        } catch {
            owsFailDebug("Deserialize failed[\(label)]: \(error).")
            return nil
        }
    }

    @objc
    public func contact(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact? {
        guard let data = Self.phoneNumberStore.getData(phoneNumber, transaction: transaction) else {
            return nil
        }
        return Self.deserializeContact(data: data, label: phoneNumber)
    }

    @objc
    public func allContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        var contacts = [Contact]()
        Self.uniqueIdStore.enumerateKeys(transaction: transaction) { (key, _) in
            guard let data = Self.uniqueIdStore.getData(key, transaction: transaction) else {
                owsFailDebug("Missing data for key: \(key).")
                return
            }
            guard let contact = Self.deserializeContact(data: data, label: key) else {
                return
            }
            contacts.append(contact)
        }
        return contacts
    }

    @objc
    public func contactsMaps(transaction: SDSAnyReadTransaction) -> ContactsMaps {
        let contacts = allContacts(transaction: transaction)
        let localNumber: String? = tsAccountManager.localNumber(with: transaction)
        return ContactsMaps.build(contacts: contacts, localNumber: localNumber)
    }

    @objc
    public func setContactsMaps(_ newContactsMaps: ContactsMaps,
                                localNumber: String?,
                                transaction: SDSAnyWriteTransaction) {

        let oldContactsMaps = self.contactsMaps(transaction: transaction)
        if oldContactsMaps.isEqualForCache(newContactsMaps) {
            Logger.verbose("Ignoring redundant contactsMap update.")
            return
        }

        Self.uniqueIdStore.removeAll(transaction: transaction)
        Self.phoneNumberStore.removeAll(transaction: transaction)

        for contact in newContactsMaps.uniqueIdToContactMap.values {
            let phoneNumbers = ContactsMaps.phoneNumbers(forContact: contact, localNumber: localNumber)
            guard !phoneNumbers.isEmpty else {
                continue
            }
            guard let contactData = Self.serializeContact(contact, label: contact.uniqueId) else {
                continue
            }

            Self.uniqueIdStore.setData(contactData, key: contact.uniqueId, transaction: transaction)

            for phoneNumber in phoneNumbers {
                Self.phoneNumberStore.setData(contactData, key: phoneNumber, transaction: transaction)
            }
        }
    }

    @objc
    public func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsManagerCacheSummary {
        // Only load the summary.
        let contactCount = Self.uniqueIdStore.numberOfKeys(transaction: transaction)
        let signalAccountCount = SignalAccount.anyCount(transaction: transaction)
        return ContactsManagerCacheSummary(contactCount: contactCount, signalAccountCount: signalAccountCount)
    }
}

// MARK: -

@objc
public class ContactsManagerCacheInMemory: NSObject, ContactsManagerCache {
    private let unfairLock = UnfairLock()

    private let contactsManagerCacheInDatabase = ContactsManagerCacheInDatabase()

    private var sortedSignalAccountsCache: [SignalAccount]?

    private var contactsMapsCache: ContactsMaps?

    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        // The in-memory cache always maintains a sorted list;
        // use that even if we don't need sorted results.
        sortedSignalAccounts(transaction: transaction)
    }

    // Order respects the systems contact sorting preference.
    @objc
    public func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        // Prefer cache.
        if let cachedValue = (unfairLock.withLock { sortedSignalAccountsCache }) {
            return cachedValue
        }
        // Fail over.
        let result = contactsManagerCacheInDatabase.sortedSignalAccounts(transaction: transaction)
        unfairLock.withLock { sortedSignalAccountsCache = result }
        return result
    }

    @objc
    public func setSortedSignalAccounts(_ signalAccounts: [SignalAccount]) {
        unfairLock.withLock {
            // Update cache.
            sortedSignalAccountsCache = signalAccounts
        }
        return contactsManagerCacheInDatabase.setSortedSignalAccounts(signalAccounts)
    }

    @objc
    public func contact(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact? {
        unfairLock.withLock {
            guard let contactsMaps = contactsMapsCache else {
                owsFailDebug("Missing contactsMaps.")
                // Don't bother failing over to contactsManagerCacheInDatabase.
                return nil
            }
            return contactsMaps.phoneNumberToContactMap[phoneNumber]
        }
    }

    @objc
    public func allContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        unfairLock.withLock {
            guard let contactsMaps = contactsMapsCache else {
                owsFailDebug("Missing contactsMaps.")
                // Don't bother failing over to contactsManagerCacheInDatabase.
                return []
            }
            return Array(contactsMaps.phoneNumberToContactMap.values)
        }
    }

    @objc
    public func contactsMaps(transaction: SDSAnyReadTransaction) -> ContactsMaps {
        unfairLock.withLock {
            guard let contactsMaps = contactsMapsCache else {
                owsFailDebug("Missing contactsMaps.")
                // Don't bother failing over to contactsManagerCacheInDatabase.
                return .empty
            }
            return contactsMaps
        }
    }

    @objc
    public func setContactsMaps(_ contactsMaps: ContactsMaps,
                                localNumber: String?,
                                transaction: SDSAnyWriteTransaction) {
        unfairLock.withLock {
            // Update cache.
            contactsMapsCache = contactsMaps
        }
        return contactsManagerCacheInDatabase.setContactsMaps(contactsMaps,
                                                              localNumber: localNumber,
                                                              transaction: transaction)
    }

    @objc
    public func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsManagerCacheSummary {

        // We consult the contactsMapsCache when sorting the
        // sortedSignalAccounts, so make sure it is set first.
        let contactsMaps = contactsManagerCacheInDatabase.contactsMaps(transaction: transaction)
        unfairLock.withLock {
            contactsMapsCache = contactsMaps
        }

        let sortedSignalAccounts = contactsManagerCacheInDatabase.sortedSignalAccounts(transaction: transaction)
        unfairLock.withLock {
            sortedSignalAccountsCache = sortedSignalAccounts
        }

        // Don't call contactsManagerCacheInDatabase.warmCaches().
        return ContactsManagerCacheSummary(contactCount: UInt(contactsMaps.uniqueIdToContactMap.count),
                                           signalAccountCount: UInt(sortedSignalAccounts.count))
    }
}

// MARK: -

@objc
extension OWSContactsManager {
    public func contact(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact? {
        contactsManagerCache.contact(forPhoneNumber: phoneNumber, transaction: transaction)
    }

    public func contactsMaps(transaction: SDSAnyReadTransaction) -> ContactsMaps {
        contactsManagerCache.contactsMaps(transaction: transaction)
    }
}
