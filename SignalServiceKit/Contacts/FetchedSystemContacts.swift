//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct FetchedSystemContacts {
    struct SystemContactRef {
        let cnContactId: String
        let userProvidedLabel: String
    }

    let phoneNumberToContactRef: [CanonicalPhoneNumber: SystemContactRef]
    let cnContactIdToContact: [String: SystemContact]

    private init(
        phoneNumberToContactRef: [CanonicalPhoneNumber: SystemContactRef],
        cnContactIdToContact: [String: SystemContact]
    ) {
        self.phoneNumberToContactRef = phoneNumberToContactRef
        self.cnContactIdToContact = cnContactIdToContact
    }

    static func parseContacts(
        _ orderedContacts: [SystemContact],
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: String?
    ) -> FetchedSystemContacts {
        // A given Contact may have multiple phone numbers.
        var phoneNumberToContactRef = [CanonicalPhoneNumber: SystemContactRef]()
        var cnContactIdToContact = [String: SystemContact]()
        let localPhoneNumber = E164(localPhoneNumber).map(CanonicalPhoneNumber.init(nonCanonicalPhoneNumber:))
        for systemContact in orderedContacts {
            var parsedPhoneNumbers = Self._parsePhoneNumbers(
                for: systemContact,
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
            cnContactIdToContact[systemContact.cnContactId] = systemContact
            for parsedPhoneNumber in parsedPhoneNumbers {
                let phoneNumber = parsedPhoneNumber.canonicalValue
                if phoneNumberToContactRef[phoneNumber] != nil {
                    // We've already picked a Contact for this number.
                    continue
                }
                phoneNumberToContactRef[phoneNumber] = SystemContactRef(
                    cnContactId: systemContact.cnContactId,
                    userProvidedLabel: parsedPhoneNumber.userProvidedLabel
                )
            }
        }
        return FetchedSystemContacts(
            phoneNumberToContactRef: phoneNumberToContactRef,
            cnContactIdToContact: cnContactIdToContact
        )
    }

    public static func parsePhoneNumbers(
        for systemContact: SystemContact,
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: CanonicalPhoneNumber?
    ) -> [CanonicalPhoneNumber] {
        return _parsePhoneNumbers(
            for: systemContact,
            phoneNumberUtil: phoneNumberUtil,
            localPhoneNumber: localPhoneNumber
        ).map { $0.canonicalValue }
    }

    private struct ParsedPhoneNumber {
        let canonicalValue: CanonicalPhoneNumber
        let userProvidedLabel: String
    }

    private static func _parsePhoneNumbers(
        for systemContact: SystemContact,
        phoneNumberUtil: PhoneNumberUtil,
        localPhoneNumber: CanonicalPhoneNumber?
    ) -> [ParsedPhoneNumber] {
        var results = [ParsedPhoneNumber]()
        for (phoneNumber, phoneNumberLabel) in systemContact.phoneNumbers {
            let parsedPhoneNumbers = parsePhoneNumber(
                phoneNumber,
                phoneNumberUtil: phoneNumberUtil,
                localPhoneNumber: localPhoneNumber
            )
            for parsedPhoneNumber in parsedPhoneNumbers {
                results.append(ParsedPhoneNumber(
                    canonicalValue: parsedPhoneNumber,
                    userProvidedLabel: phoneNumberLabel ?? ""
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
            guard let phoneNumber = E164(phoneNumberObj.e164) else {
                owsFailDebug("Couldn't convert parsed phone number to E164")
                continue
            }
            results.append(CanonicalPhoneNumber(nonCanonicalPhoneNumber: phoneNumber))
        }
        return results
    }
}
