//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Provides data on system contacts.
///
/// On primary devices, this is populated from the local address book. On
/// linked devices, this is populated from the primary's address book (via
/// contact syncs/storage service).
protocol SystemContactsDataProvider {
    /// Fetches a single contact from the underlying data store.
    func fetchSystemContact(for phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact?

    /// Fetches all contacts from the underlying data store.
    func fetchAllSystemContacts(transaction: SDSAnyReadTransaction) -> [Contact]
}

// MARK: -

final class PrimaryDeviceSystemContactsDataProvider: SystemContactsDataProvider {

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

    func fetchSystemContact(for phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact? {
        guard let data = Self.phoneNumberStore.getData(phoneNumber, transaction: transaction) else {
            return nil
        }
        return Self.deserializeContact(data: data, label: phoneNumber)
    }

    func fetchAllSystemContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        var contacts = [Contact]()
        // reading and materializing all entries at once is *much* faster
        Self.contactsStore.enumerateKeys(transaction: transaction) { (key, _) in
            // the entries may be written in chunks to reduce memory footprint
            if let data = Self.contactsStore.getData(key, transaction: transaction), let array = Self.deserializeContacts(data: data) {
                contacts.append(contentsOf: array)
                Logger.verbose("did read chunk with \(array.count) entries. We have now \(contacts.count) entries in total")
            }
        }
        return contacts
    }

    func setContactsMaps(
        _ newContactsMaps: ContactsMaps,
        oldContactsMaps: () -> ContactsMaps,
        localNumber: String?,
        transaction: SDSAnyWriteTransaction
    ) {
        // This store is deprecated, so clean it up during other modifications.
        Self.deprecated_uniqueIdStore.removeAll(transaction: transaction)

        guard !newContactsMaps.uniqueIdToContactMap.isEmpty else {
            Logger.info("wiping contacts info in db")
            Self.phoneNumberStore.removeAll(transaction: transaction)
            Self.contactsStore.removeAll(transaction: transaction)
            return
        }

        var shallPersist = true
        let oldContactsMaps = oldContactsMaps()

        // If there aren't any changes, we don't need to modify anything.
        if oldContactsMaps.isEqualForCache(newContactsMaps) {
            Logger.verbose("Ignoring redundant contactsMap update.")
            shallPersist = false
            return
        }

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
        if shallPersist {
            persist(contacts: newContactsMaps.allContacts, transaction: transaction)
        }
    }

    private func persist(contacts: [Contact], transaction: SDSAnyWriteTransaction) {
        let chunkSize = 500
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

// MARK: -

final class LinkedDeviceSystemContactsDataProvider {
    private let modelReadCaches: ModelReadCaches

    init(modelReadCaches: ModelReadCaches) {
        self.modelReadCaches = modelReadCaches
    }

    convenience init() {
        struct GlobalDependencies: Dependencies {}
        self.init(modelReadCaches: GlobalDependencies.modelReadCaches)
    }
}

extension LinkedDeviceSystemContactsDataProvider: SystemContactsDataProvider {
    func fetchSystemContact(for phoneNumber: String, transaction: SDSAnyReadTransaction) -> Contact? {
        modelReadCaches.signalAccountReadCache.getSignalAccount(
            address: SignalServiceAddress(phoneNumber: phoneNumber),
            transaction: transaction
        )?.contact
    }

    func fetchAllSystemContacts(transaction: SDSAnyReadTransaction) -> [Contact] {
        SignalAccount.anyFetchAll(transaction: transaction).compactMap { $0.contact }
    }
}
