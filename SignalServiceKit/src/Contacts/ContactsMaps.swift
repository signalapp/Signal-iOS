//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@objc
public class ContactsMaps: NSObject {
    @objc
    public let uniqueIdToContactMap: [String: Contact]

    @objc
    public let phoneNumberToContactMap: [String: Contact]

    @objc
    public var allContacts: [Contact] { Array(uniqueIdToContactMap.values) }

    required init(
        uniqueIdToContactMap: [String: Contact],
        phoneNumberToContactMap: [String: Contact]
    ) {
        self.uniqueIdToContactMap = uniqueIdToContactMap
        self.phoneNumberToContactMap = phoneNumberToContactMap
    }

    static let empty: ContactsMaps = ContactsMaps(uniqueIdToContactMap: [:], phoneNumberToContactMap: [:])

    // Builds a map of phone number-to-Contact.
    // A given Contact may have multiple phone numbers.
    @objc
    public static func build(
        contacts: [Contact],
        localNumber: String?
    ) -> ContactsMaps {
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
        return ContactsMaps(
            uniqueIdToContactMap: uniqueIdToContactMap,
            phoneNumberToContactMap: phoneNumberToContactMap
        )
    }

    static func phoneNumbers(forContact contact: Contact, localNumber: String?) -> [String] {
        let phoneNumbers: [String] = contact.parsedPhoneNumbers.compactMap { phoneNumber in
            guard let phoneNumberE164 = phoneNumber.toE164().nilIfEmpty else {
                return nil
            }

            return phoneNumberE164
        }

        if let localNumber, phoneNumbers.contains(localNumber) {
            // Ignore any system contact records for the local contact. For the local
            // user we never want to show the avatar / name that you have entered for
            // yourself in your system contacts. Instead, we always want to display
            // your profile name and avatar.
            return []
        }

        return phoneNumbers
    }

    public func isEqualForCache(_ other: ContactsMaps) -> Bool {
        guard uniqueIdToContactMap.count == other.uniqueIdToContactMap.count else {
            return false
        }
        for (key, contact) in uniqueIdToContactMap {
            guard let otherContact = other.uniqueIdToContactMap[key], contact.isEqualForCache(otherContact) else {
                return false
            }
        }
        return true
    }
}
