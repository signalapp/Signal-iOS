//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public protocol ContactsState: AnyObject {
    func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount]

    // Order respects the systems contact sorting preference.
    func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount]

    func setSortedSignalAccounts(_ signalAccounts: [SignalAccount])

    func setContactsMaps(_ contactsMaps: ContactsMaps,
                         localNumber: String?,
                         transaction: SDSAnyWriteTransaction)

    func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsStateSummary
}

// MARK: -

@objc
public class ContactsStateSummary: NSObject {
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
        return contact.parsedPhoneNumbers.compactMap { phoneNumber in
            guard let phoneNumberE164 = phoneNumber.toE164().nilIfEmpty else {
                return nil
            }

            // Ignore any system contact records for the local contact.
            // For the local user we never want to show the avatar /
            // name that you have entered for yourself in your system
            // contacts. Instead, we always want to display your profile
            // name and avatar.
            let isLocalContact = phoneNumberE164 == localNumber
            guard !isLocalContact else {
                return nil
            }

            return phoneNumberE164
        }
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
public class ContactsStateInDatabase: NSObject, ContactsState {
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

    private static let uniqueIdStore = SDSKeyValueStore(collection: "ContactsState.uniqueIdStore")
    private static let phoneNumberStore = SDSKeyValueStore(collection: "ContactsState.phoneNumberStore")

    fileprivate func loadContactsMaps(transaction: SDSAnyReadTransaction) -> ContactsMaps {
        var contacts = [Contact]()
        Self.uniqueIdStore.enumerateKeys(transaction: transaction) { (key, _) in
            guard let data = Self.uniqueIdStore.getData(key, transaction: transaction) else {
                owsFailDebug("Missing data for key: \(key).")
                return
            }
            do {
                guard let contact = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Contact else {
                    owsFailDebug("Invalid value: \(key).")
                    return
                }
                contacts.append(contact)
            } catch {
                owsFailDebug("Deserialize failed[\(key)]: \(error).")
            }
        }
        let localNumber: String? = tsAccountManager.localNumber(with: transaction)
        return ContactsMaps.build(contacts: contacts, localNumber: localNumber)
    }

    @objc
    public func setContactsMaps(_ newContactsMaps: ContactsMaps,
                                localNumber: String?,
                                transaction: SDSAnyWriteTransaction) {

        let oldContactsMaps = loadContactsMaps(transaction: transaction)
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

            let contactData = NSKeyedArchiver.archivedData(withRootObject: contact)
            guard !contactData.isEmpty else {
                owsFailDebug("Could not serialize contact.")
                continue
            }

            Self.uniqueIdStore.setData(contactData, key: contact.uniqueId, transaction: transaction)

            for phoneNumber in phoneNumbers {
                Self.phoneNumberStore.setData(contactData, key: phoneNumber, transaction: transaction)
            }
        }
    }

    @objc
    public func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsStateSummary {
        // Only load the summary.
        let contactCount = Self.uniqueIdStore.numberOfKeys(transaction: transaction)
        let signalAccountCount = SignalAccount.anyCount(transaction: transaction)
        return ContactsStateSummary(contactCount: contactCount, signalAccountCount: signalAccountCount)
    }
}

// MARK: -

@objc
public class ContactsStateInMemory: NSObject, ContactsState {
    private let unfairLock = UnfairLock()

    private let contactsStateInDatabase = ContactsStateInDatabase()

    private var sortedSignalAccountsCache: [SignalAccount]?

    private var contactsMapsCache: ContactsMaps?

    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        // Prefer cache.
        if let cachedValue = (unfairLock.withLock { sortedSignalAccountsCache }) {
            return cachedValue
        }
        // Fail over.
        return contactsStateInDatabase.unsortedSignalAccounts(transaction: transaction)
    }

    // Order respects the systems contact sorting preference.
    @objc
    public func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        // Prefer cache.
        if let cachedValue = (unfairLock.withLock { sortedSignalAccountsCache }) {
            return cachedValue
        }
        // Fail over.
        return contactsStateInDatabase.sortedSignalAccounts(transaction: transaction)
    }

    @objc
    public func setSortedSignalAccounts(_ signalAccounts: [SignalAccount]) {
        unfairLock.withLock {
            // Update cache.
            sortedSignalAccountsCache = signalAccounts
        }
        return contactsStateInDatabase.setSortedSignalAccounts(signalAccounts)
    }

    @objc
    public func setContactsMaps(_ contactsMaps: ContactsMaps,
                                localNumber: String?,
                                transaction: SDSAnyWriteTransaction) {
        unfairLock.withLock {
            // Update cache.
            contactsMapsCache = contactsMaps
        }
        return contactsStateInDatabase.setContactsMaps(contactsMaps,
                                                       localNumber: localNumber,
                                                       transaction: transaction)
    }

    @objc
    public func warmCaches(transaction: SDSAnyReadTransaction) -> ContactsStateSummary {

        let sortedSignalAccounts = contactsStateInDatabase.sortedSignalAccounts(transaction: transaction)
        let contactsMaps = contactsStateInDatabase.loadContactsMaps(transaction: transaction)

        unfairLock.withLock {
            sortedSignalAccountsCache = sortedSignalAccounts
            contactsMapsCache = contactsMaps
        }

        // Don't call contactsStateInDatabase.warmCaches().
        return ContactsStateSummary(contactCount: UInt(contactsMaps.uniqueIdToContactMap.count),
                                    signalAccountCount: UInt(sortedSignalAccounts.count))
    }
}
