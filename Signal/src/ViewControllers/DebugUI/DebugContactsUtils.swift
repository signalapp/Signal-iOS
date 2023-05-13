//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import SignalMessaging
import SignalServiceKit

#if USE_DEBUG_UI

class DebugContactsUtils: Dependencies {

    // MARK: Random Contacts

    static func randomPhoneNumber() -> String {
        var result: String
        var numberOfDigits: UInt
        if Bool.random() {
            // Generate a US phone number.
            result = "+1"
            numberOfDigits = 10
        } else {
            // Generate a UK phone number.
            result = "+441"
            numberOfDigits = 9
        }
        for _ in 0..<numberOfDigits {
            result += String(Int.random(in: 0...9))
        }
        return result
    }

    static func createRandomContacts(_ count: UInt, contactHandler: ((CNContact, Int, inout Bool) -> Void)? = nil) {
        guard count > 0 else { return }

        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authorizationStatus != .denied && authorizationStatus != .restricted else {
            OWSActionSheets.showErrorAlert(message: "No Contacts access.")
            return
        }

        // Request access
        guard authorizationStatus == .authorized else {
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, error in
                guard granted && error == nil else {
                    DispatchQueue.main.async {
                        OWSActionSheets.showErrorAlert(message: "No Contacts access.")
                    }
                    return
                }
                DispatchQueue.main.async {
                    createRandomContacts(count, contactHandler: contactHandler)
                }
            }
            return
        }

        let maxBatchSize: UInt = 10
        let batchSize = min(maxBatchSize, count)
        var remainder = count - batchSize
        createRandomContactsBatch(batchSize, contactHandler: contactHandler) {
            guard remainder > 0 else { return }
            DispatchQueue.main.async {
                createRandomContacts(remainder, contactHandler: contactHandler)
            }
        }
    }

    private static func createRandomContactsBatch(
        _ count: UInt,
        contactHandler: ((CNContact, Int, inout Bool) -> Void)?,
        completion: () -> Void
    ) {
        Logger.debug("createRandomContactsBatch: \(count)")

        var contacts = [CNContact]()

        // 50% chance of fake contact having an avatar
        let percentWithAvatar = 50
        let percentWithLargeAvatar = 25
        let minimumAvatarDiameter: UInt = 200
        let maximimAvatarDiameter: UInt = 800

        let saveRequest = CNSaveRequest()
        for _ in 0..<count { autoreleasepool {
            let contact = CNMutableContact()
            contact.familyName = "Rando-" + CommonGenerator.lastName()
            contact.givenName = CommonGenerator.firstName()

            let homePhone = CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: randomPhoneNumber()))
            contact.phoneNumbers = [ homePhone ]

            let avatarSeed = UInt.random(in: 0...99)
            if avatarSeed < percentWithAvatar {
                let shouldUseLargeAvatar = avatarSeed < percentWithLargeAvatar
                let avatarDiameter: UInt = {
                    if shouldUseLargeAvatar {
                        return maximimAvatarDiameter
                    }
                    return UInt.random(in: minimumAvatarDiameter...maximimAvatarDiameter)
                }()
                let avatarImage: UIImage?
                if shouldUseLargeAvatar {
                    avatarImage = AvatarBuilder.buildNoiseAvatar(diameterPoints: avatarDiameter)
                } else {
                    avatarImage = AvatarBuilder.buildRandomAvatar(diameterPoints: avatarDiameter)
                }
                if let avatarImageData = avatarImage?.jpegData(compressionQuality: 0.9) {
                    contact.imageData = avatarImageData
                    Logger.debug("avatar size: \(avatarImageData.count) bytes")
                }
            }

            contacts.append(contact)
            saveRequest.add(contact, toContainerWithIdentifier: nil)
        }}

        Logger.info("Saving fake contacts: \(contacts.count)")
        do {
            try CNContactStore().execute(saveRequest)
            if let contactHandler {
                for (index, contact) in contacts.enumerated() {
                    var stop = false
                    contactHandler(contact, index, &stop)
                    if stop {
                        break
                    }
                }
            }
        } catch {
            owsFailDebug("Error saving fake contacts: \(error)")
            DispatchQueue.main.async {
                OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
            }
        }

        completion()
    }

    // MARK: Contact Deletion

    static func deleteAllContacts() {
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authorizationStatus != .denied && authorizationStatus != .restricted else {
            OWSActionSheets.showErrorAlert(message: "No Contacts access.")
            return
        }

        // Request access
        guard authorizationStatus == .authorized else {
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, error in
                guard granted && error == nil else {
                    DispatchQueue.main.async {
                        OWSActionSheets.showErrorAlert(message: "No Contacts access.")
                    }
                    return
                }
                DispatchQueue.main.async {
                    deleteAllContacts()
                }
            }
            return
        }

        deleteContactsWithFilter { _ in return true }
    }

    static func deleteRandomContacts() {
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authorizationStatus != .denied && authorizationStatus != .restricted else {
            OWSActionSheets.showErrorAlert(message: "No Contacts access.")
            return
        }

        // Request access
        guard authorizationStatus == .authorized else {
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, error in
                guard granted && error == nil else {
                    DispatchQueue.main.async {
                        OWSActionSheets.showErrorAlert(message: "No Contacts access.")
                    }
                    return
                }
                DispatchQueue.main.async {
                    deleteRandomContacts()
                }
            }
            return
        }

        deleteContactsWithFilter { contact in
            return contact.familyName.hasPrefix("Rando-")
        }
    }

    private static func deleteContactsWithFilter(_ filter: (CNContact) -> Bool) {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName) as CNKeyDescriptor
        ]

        let contactStore = CNContactStore()
        let saveRequest = CNSaveRequest()
        do {
            try contactStore.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keysToFetch)) { contact, _ in
                if filter(contact) {
                    saveRequest.delete(contact.mutableCopy() as! CNMutableContact)
                }
            }
            try contactStore.execute(saveRequest)
        } catch {
            Logger.error("\(error)")
            OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
        }
    }

    // MARK: -

    static func logSignalAccounts() {
        databaseStorage.read { transaction in
            SignalAccount.anyEnumerate(transaction: transaction, batchingPreference: .batched()) { (account: SignalAccount, _) in
                Logger.verbose("---- \(account.uniqueId),  \(account.recipientAddress),  \(String(describing: account.contactFirstName)),  \(String(describing: account.contactLastName)),  \(String(describing: account.contactNicknameIfAvailable())), ")
            }
        }
    }
}

#endif
