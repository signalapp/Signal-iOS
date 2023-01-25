//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    public let phoneNumberCount: UInt

    @objc
    public let signalAccountCount: UInt

    required init(phoneNumberCount: UInt, signalAccountCount: UInt) {
        self.phoneNumberCount = phoneNumberCount
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

    private static let deprecated_uniqueIdStore = SDSKeyValueStore(collection: "ContactsManagerCache.uniqueIdStore")
    private static let phoneNumberStore = SDSKeyValueStore(collection: "ContactsManagerCache.phoneNumberStore")
    private static let contactsStore = SDSKeyValueStore(collection: "ContactsManagerCache.allContacts")

    private static func serializeContact(_ contact: Contact, label: String) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: contact, requiringSecureCoding: false)
        } catch {
            owsFailDebug("Could not serialize contact (\(label)): \(error)")
            return nil
        }
    }

    private static func serializeContacts(_ contacts: [Contact]) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: contacts, requiringSecureCoding: false)
        } catch {
            owsFailDebug("Could not serialize contacts: \(error)")
            return nil
        }
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

    private static func deserializeContacts(data: Data) -> [Contact]? {
        do {
            guard let contacts = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [Contact] else {
                owsFailDebug("Invalid contacts array value.")
                return nil
            }
            return contacts
        } catch {
            owsFailDebug("Deserialize contacts array failed: \(error).")
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
        InstrumentsMonitor.measure(category: "runtime", parent: "ContactsManagerCache", name: "allContacts") {
            // reading and materializing all entries at once is *much* faster
            Self.contactsStore.enumerateKeys(transaction: transaction) { (key, _) in
                // the entries may be written in chunks to reduce memory footprint
                if let data = Self.contactsStore.getData(key, transaction: transaction), let array = Self.deserializeContacts(data: data) {
                    contacts.append(contentsOf: array)
                    Logger.verbose("did read chunk with \(array.count) entries. We have now \(contacts.count) entries in total")
                }
            }
            if contacts.isEmpty {
                // this legacy code path should be executed only once
                Self.deprecated_uniqueIdStore.enumerateKeys(transaction: transaction) { (key, _) in
                    let data = Self.deprecated_uniqueIdStore.getData(key, transaction: transaction)
                    guard let data = data else {
                        owsFailDebug("Missing data for key: \(key).")
                        return
                    }
                    let contact = Self.deserializeContact(data: data, label: key)
                    guard let contact = contact else {
                        return
                    }
                    contacts.append(contact)
                }
                Logger.verbose("did read \(contacts.count) entries using legacy code path")
                if !contacts.isEmpty {
                    DispatchQueue.sharedBackground.async {
                        self.databaseStorage.write { transaction in
                            self.persist(contacts: contacts, transaction: transaction)
                        }
                    }
                }
            }
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
    public func setContactsMaps(
        _ newContactsMaps: ContactsMaps,
        localNumber: String?,
        transaction: SDSAnyWriteTransaction
    ) {
        self.setContactsMaps(newContactsMaps, localNumber: localNumber, transaction: transaction, oldContactsMaps: nil)
    }

    fileprivate func setContactsMaps(
        _ newContactsMaps: ContactsMaps,
        localNumber: String?,
        transaction: SDSAnyWriteTransaction,
        oldContactsMaps: ContactsMaps?
    ) {
        guard !newContactsMaps.uniqueIdToContactMap.isEmpty else {
            Logger.info("wiping contacts info in db")
            InstrumentsMonitor.measure(category: "runtime", parent: "ContactsManagerCache", name: "wipe") {
                Self.deprecated_uniqueIdStore.removeAll(transaction: transaction)
                Self.phoneNumberStore.removeAll(transaction: transaction)
                Self.contactsStore.removeAll(transaction: transaction)
            }
            return
        }

        var shallPersist = true
        InstrumentsMonitor.measure(category: "runtime", parent: "ContactsManagerCache", name: "update") {
            let oldContactsMaps = oldContactsMaps ?? contactsMaps(transaction: transaction)

            // If there aren't any changes, we don't need to modify anything.
            if oldContactsMaps.isEqualForCache(newContactsMaps) {
                Logger.verbose("Ignoring redundant contactsMap update.")
                shallPersist = false
                return
            }

            // Once we load the old contact maps, we can delete `uniqueIdStore`
            // entirely, which isn't needed after we migrate.
            Self.deprecated_uniqueIdStore.removeAll(transaction: transaction)

            func removePhoneNumbers(for contact: Contact) {
                let phoneNumbers = ContactsMaps.phoneNumbers(forContact: contact, localNumber: localNumber)
                Self.phoneNumberStore.removeValues(forKeys: phoneNumbers, transaction: transaction)
            }

            func addPhoneNumbers(for contact: Contact) {
                guard let contactData = Self.serializeContact(contact, label: contact.uniqueId) else {
                    return
                }
                for phoneNumber in ContactsMaps.phoneNumbers(forContact: contact, localNumber: localNumber) {
                    Self.phoneNumberStore.setData(contactData, key: phoneNumber, transaction: transaction)
                }
            }

            for (contactUUID, oldContact) in oldContactsMaps.uniqueIdToContactMap {
                guard newContactsMaps.uniqueIdToContactMap[contactUUID] == nil else {
                    continue
                }
                // The contact no longer exists -- remove it.
                Logger.verbose("deleting system contact with UUID \(contactUUID)")
                removePhoneNumbers(for: oldContact)
            }

            for (contactUUID, newContact) in newContactsMaps.uniqueIdToContactMap {
                switch oldContactsMaps.uniqueIdToContactMap[contactUUID] {
                case .some(let oldContact) where oldContact.isEqualForCache(newContact):
                    break
                case .some(let oldContact):
                    Logger.verbose("updating existing system contact with UUID \(contactUUID)")
                    removePhoneNumbers(for: oldContact)
                    addPhoneNumbers(for: newContact)
                case .none:
                    Logger.verbose("adding new system contact with UUID \(contactUUID)")
                    addPhoneNumbers(for: newContact)
                }
            }
        }
        if shallPersist {
            persist(contacts: newContactsMaps.allContacts, transaction: transaction)
        }
    }

    @objc
    public func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsManagerCacheSummary {
        // Only load the summary.
        let phoneNumberCount = Self.phoneNumberStore.numberOfKeys(transaction: transaction)
        let signalAccountCount = SignalAccount.anyCount(transaction: transaction)
        return ContactsManagerCacheSummary(phoneNumberCount: phoneNumberCount, signalAccountCount: signalAccountCount)
    }

    private func persist(contacts: [Contact], transaction: SDSAnyWriteTransaction) {
        let chunkSize = 500
        InstrumentsMonitor.measure(category: "runtime", parent: "ContactsManagerCache", name: "setContactsStore") {
            Logger.info("persisting \(contacts.count) entries using chunk size of \(chunkSize)")
            Self.contactsStore.removeAll(transaction: transaction)
            var contacts = contacts[...]
            var chunkNr = 0
            while !contacts.isEmpty {
                chunkNr += 1
                let chunk = Array(contacts.prefix(chunkSize))
                contacts = contacts.dropFirst(chunkSize)
                Logger.info("writing chunk#\(chunkNr) with \(chunk.count) entries")
                if let data = Self.serializeContacts(chunk) {
                    Self.contactsStore.setData(data, key: "\(chunkNr)", transaction: transaction)
                } else {
                    owsFailDebug("chunk#\(chunkNr) can not be serialized")
                }
            }
        }
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
                return contactsManagerCacheInDatabase.contact(forPhoneNumber: phoneNumber, transaction: transaction)
            }
            return contactsMaps.phoneNumberToContactMap[phoneNumber]
        }
    }

    @objc
    public func allContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        unfairLock.withLock {
            guard let contactsMaps = contactsMapsCache else {
                return contactsManagerCacheInDatabase.allContacts(transaction: transaction)
            }
            return contactsMaps.allContacts
        }
    }

    @objc
    public func contactsMaps(transaction: SDSAnyReadTransaction) -> ContactsMaps {
        unfairLock.withLock {
            guard let contactsMaps = contactsMapsCache else {
                return contactsManagerCacheInDatabase.contactsMaps(transaction: transaction)
            }
            return contactsMaps
        }
    }

    @objc
    public func setContactsMaps(
        _ contactsMaps: ContactsMaps,
        localNumber: String?,
        transaction: SDSAnyWriteTransaction
    ) {
        let oldContactsMaps = unfairLock.withLock {
            let oldValue = contactsMapsCache
            contactsMapsCache = contactsMaps
            return oldValue
        }
        contactsManagerCacheInDatabase.setContactsMaps(
            contactsMaps,
            localNumber: localNumber,
            transaction: transaction,
            oldContactsMaps: oldContactsMaps
        )
    }

    @objc
    public func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsManagerCacheSummary {
        var phoneNumberCount: UInt?
        var signalAccountCount: UInt?
        InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmContactsManagerCache") {
            // We consult the contactsMapsCache when sorting the
            // sortedSignalAccounts, so make sure it is set first.
            let contactsMaps = contactsManagerCacheInDatabase.contactsMaps(transaction: transaction)
            unfairLock.withLock {
                contactsMapsCache = contactsMaps
            }
            phoneNumberCount = UInt(contactsMaps.phoneNumberToContactMap.count)

            let sortedSignalAccounts = contactsManagerCacheInDatabase.sortedSignalAccounts(transaction: transaction)
            unfairLock.withLock {
                sortedSignalAccountsCache = sortedSignalAccounts
            }
            signalAccountCount = UInt(sortedSignalAccounts.count)
        }
        // Don't call contactsManagerCacheInDatabase.warmCaches().
        return ContactsManagerCacheSummary(phoneNumberCount: phoneNumberCount!, signalAccountCount: signalAccountCount!)
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
