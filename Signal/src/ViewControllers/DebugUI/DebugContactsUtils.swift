//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugContactsUtils {

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

    @MainActor
    static func createRandomContacts(
        _ count: UInt,
        contactHandler: ((CNContact, Int, inout Bool) async -> Void)? = nil
    ) async {
        guard count > 0 else { return }

        guard await requestContactsAuthorizationIfNecessary() else {
            OWSActionSheets.showErrorAlert(message: "No Contacts access.")
            return
        }

        var batch: UInt
        var remainder = count
        repeat {
            batch = min(remainder, 10)
            remainder -= batch
            await createRandomContactsBatch(batch, contactHandler: contactHandler)
        } while remainder > 0
    }

    private static func createRandomContactsBatch(
        _ count: UInt,
        contactHandler: ((CNContact, Int, inout Bool) async -> Void)?
    ) async {
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
                    await contactHandler(contact, index, &stop)
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
    }

    // MARK: Contact Deletion

    @MainActor
    static func deleteAllContacts() async {
        guard await requestContactsAuthorizationIfNecessary() else {
            OWSActionSheets.showErrorAlert(message: "No Contacts access.")
            return
        }

        do {
            try deleteContactsWithFilter { _ in return true }
        } catch {
            Logger.error("\(error)")
            OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
        }
    }

    @MainActor
    static func deleteRandomContacts() async {
        guard await requestContactsAuthorizationIfNecessary() else {
            OWSActionSheets.showErrorAlert(message: "No Contacts access.")
            return
        }

        do {
            try deleteContactsWithFilter { contact in
                return contact.familyName.hasPrefix("Rando-")
            }
        } catch {
            Logger.error("\(error)")
            OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
        }
    }

    private static func deleteContactsWithFilter(_ filter: (CNContact) -> Bool) throws {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName) as CNKeyDescriptor
        ]

        let contactStore = CNContactStore()
        let saveRequest = CNSaveRequest()
        try contactStore.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keysToFetch)) { contact, _ in
            if filter(contact) {
                saveRequest.delete(contact.mutableCopy() as! CNMutableContact)
            }
        }
        try contactStore.execute(saveRequest)
    }

    private static func requestContactsAuthorizationIfNecessary() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .denied, .restricted:
            return false

        case .limited, .authorized:
            return true

        case .notDetermined:
            fallthrough

        // If we don't know what this authorization status means, still
        // optimistically try to request access.
        @unknown default:
            do {
                let store = CNContactStore()
                return try await store.requestAccess(for: .contacts)
            } catch {
                return false
            }
        }
    }
}

#endif
