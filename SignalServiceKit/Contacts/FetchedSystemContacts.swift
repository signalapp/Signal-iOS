//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public struct FetchedSystemContacts {
    struct ContactRef {
        let uniqueId: String
        let userProvidedLabel: String
    }

    let phoneNumberToContactRef: [CanonicalPhoneNumber: ContactRef]
    let uniqueIdToContact: [String: Contact]

    private init(
        phoneNumberToContactRef: [CanonicalPhoneNumber: ContactRef],
        uniqueIdToContact: [String: Contact]
    ) {
        self.phoneNumberToContactRef = phoneNumberToContactRef
        self.uniqueIdToContact = uniqueIdToContact
    }

    public static func parseContacts(
        _ orderedContacts: [Contact],
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: String?
    ) -> FetchedSystemContacts {
        // A given Contact may have multiple phone numbers.
        var phoneNumberToContactRef = [CanonicalPhoneNumber: ContactRef]()
        var uniqueIdToContact = [String: Contact]()
        let localPhoneNumber = E164(localPhoneNumber).map(CanonicalPhoneNumber.init(nonCanonicalPhoneNumber:))
        for contact in orderedContacts {
            var parsedPhoneNumbers = Self._parsePhoneNumbers(
                for: contact,
                phoneNumberUtil: phoneNumberUtil,
                localPhoneNumber: localPhoneNumber
            )
            // Ignore any system contact records for the local contact. For the local
            // user we never want to show the avatar / name that you have entered for
            // yourself in your system contacts. Instead, we always want to display
            // your profile name and avatar.
            parsedPhoneNumbers.removeAll(where: { $0.canonicalValue == localPhoneNumber })
            if parsedPhoneNumbers.isEmpty {
                continue
            }
            uniqueIdToContact[contact.uniqueId] = contact
            for parsedPhoneNumber in parsedPhoneNumbers {
                let phoneNumber = parsedPhoneNumber.canonicalValue
                if phoneNumberToContactRef[phoneNumber] != nil {
                    // We've already picked a Contact for this number.
                    continue
                }
                phoneNumberToContactRef[phoneNumber] = ContactRef(
                    uniqueId: contact.uniqueId,
                    userProvidedLabel: parsedPhoneNumber.userProvidedLabel
                )
            }
        }
        return FetchedSystemContacts(
            phoneNumberToContactRef: phoneNumberToContactRef,
            uniqueIdToContact: uniqueIdToContact
        )
    }

    public static func parsePhoneNumbers(
        for contact: Contact,
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: CanonicalPhoneNumber?
    ) -> [CanonicalPhoneNumber] {
        return _parsePhoneNumbers(
            for: contact,
            phoneNumberUtil: phoneNumberUtil,
            localPhoneNumber: localPhoneNumber
        ).map { $0.canonicalValue }
    }

    private struct ParsedPhoneNumber {
        let canonicalValue: CanonicalPhoneNumber
        let userProvidedLabel: String
    }

    private static func _parsePhoneNumbers(
        for contact: Contact,
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: CanonicalPhoneNumber?
    ) -> [ParsedPhoneNumber] {
        var results = [ParsedPhoneNumber]()
        for userTextPhoneNumber in contact.userTextPhoneNumbers {
            let phoneNumbers = parsePhoneNumber(
                userTextPhoneNumber,
                phoneNumberUtil: phoneNumberUtil,
                localPhoneNumber: localPhoneNumber
            )
            for phoneNumber in phoneNumbers {
                results.append(ParsedPhoneNumber(
                    canonicalValue: phoneNumber,
                    userProvidedLabel: contact.userTextPhoneNumberLabels[userTextPhoneNumber] ?? ""
                ))
            }
        }
        return results
    }

    public static func parsePhoneNumber(
        _ userTextPhoneNumber: String,
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: CanonicalPhoneNumber?
    ) -> [CanonicalPhoneNumber] {
        let phoneNumbers = phoneNumberUtil.parsePhoneNumbers(
            userSpecifiedText: userTextPhoneNumber,
            localPhoneNumber: localPhoneNumber?.rawValue.stringValue
        )
        var results = [CanonicalPhoneNumber]()
        for phoneNumberObj in phoneNumbers {
            guard let phoneNumber = E164(phoneNumberObj.toE164()) else {
                owsFailDebug("Couldn't convert parsed phone number to E164")
                continue
            }
            results.append(CanonicalPhoneNumber(nonCanonicalPhoneNumber: phoneNumber))
        }
        return results
    }
}
