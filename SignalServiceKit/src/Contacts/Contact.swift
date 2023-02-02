//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

// MARK: - Equality

public extension Contact {
    func isEqualForCache(_ other: Contact) -> Bool {
        guard namesAreEqual(toOther: other),
              self.comparableNameFirstLast == other.comparableNameFirstLast,
              self.comparableNameLastFirst == other.comparableNameLastFirst,
              self.uniqueId == other.uniqueId,
              self.cnContactId == other.cnContactId,
              self.isFromLocalAddressBook == other.isFromLocalAddressBook,
              self.phoneNumberNameMap == other.phoneNumberNameMap else {
                  return false
              }

        // Ignore ordering of these properties.
        guard Set(self.userTextPhoneNumbers) == Set(other.userTextPhoneNumbers),
              Set(self.emails) == Set(other.emails) else {
                  return false
              }

        // Ignore ordering of this property,
        // Don't rely on equality of PhoneNumber.
        let parsedPhoneNumbersSelf = Set(self.parsedPhoneNumbers.compactMap { $0.toE164() })
        let parsedPhoneNumbersOther = Set(other.parsedPhoneNumbers.compactMap { $0.toE164() })
        guard parsedPhoneNumbersSelf == parsedPhoneNumbersOther else {
            return false
        }

        return true
    }

    func namesAreEqual(toOther other: Contact) -> Bool {
        guard
            self.firstName == other.firstName,
            self.lastName == other.lastName,
            self.nickname == other.nickname,
            self.fullName == other.fullName
        else {
            return false
        }

        return true
    }
}

// MARK: - Phone Numbers

public extension Contact {
    func hasPhoneNumber(_ phoneNumber: String?) -> Bool {
        for parsedPhoneNumber in parsedPhoneNumbers {
            if parsedPhoneNumber.toE164() == phoneNumber {
                return true
            }
        }
        return false
    }

    private func phoneNumberLabel(for address: SignalServiceAddress) -> String {
        if let phoneNumber = address.phoneNumber, let phoneNumberLabel = phoneNumberNameMap[phoneNumber] {
            return phoneNumberLabel
        }
        return OWSLocalizedString(
            "PHONE_NUMBER_TYPE_UNKNOWN",
            comment: "Label used when we don't what kind of phone number it is (e.g. mobile/work/home)."
        )
    }

    func uniquePhoneNumberLabel(for address: SignalServiceAddress, relatedAddresses: [SignalServiceAddress]) -> String? {
        owsAssertDebug(address.isValid)

        owsAssertDebug(relatedAddresses.contains(address))
        guard relatedAddresses.count > 1 else {
            return nil
        }

        // 1. Find the address type of this account.
        let addressLabel = phoneNumberLabel(for: address).filterForDisplay

        // 2. Find all addresses for this contact of the same type.
        let addressesWithTheSameLabel = relatedAddresses.filter {
            addressLabel == phoneNumberLabel(for: $0).filterForDisplay
        }.stableSort()

        // 3. Figure out if this is "Mobile 0" or "Mobile 1".
        guard let thisAddressIndex = addressesWithTheSameLabel.firstIndex(of: address) else {
            owsFailDebug("Couldn't find the address we were trying to match.")
            return addressLabel
        }

        // 4. If there's only one "Mobile", don't add the " 0" or " 1" suffix.
        guard addressesWithTheSameLabel.count > 1 else {
            return addressLabel
        }

        // 5. If there's two or more "Mobile" numbers, specify which this is.
        let format = OWSLocalizedString(
            "PHONE_NUMBER_TYPE_AND_INDEX_NAME_FORMAT",
            comment: "Format for phone number label with an index. Embeds {{Phone number label (e.g. 'home')}} and {{index, e.g. 2}}."
        )
        return String(format: format, addressLabel, OWSFormat.formatInt(thisAddressIndex)).filterForDisplay
    }
}

// MARK: - Convenience init

public extension Contact {
    convenience init(
        address: SignalServiceAddress,
        phoneNumberLabel: String,
        givenName: String?,
        familyName: String?,
        nickname: String?,
        fullName: String
    ) {
        var userTextPhoneNumbers: [String] = []
        var phoneNumberNameMap: [String: String] = [:]
        var parsedPhoneNumbers: [PhoneNumber] = []
        if
            let phoneNumber = address.phoneNumber,
            let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumber)
        {
            userTextPhoneNumbers.append(phoneNumber)
            parsedPhoneNumbers.append(parsedPhoneNumber)
            phoneNumberNameMap[parsedPhoneNumber.toE164()] = phoneNumberLabel
        }

        self.init(
            uniqueId: UUID().uuidString,
            cnContactId: nil,
            firstName: givenName,
            lastName: familyName,
            nickname: nickname,
            fullName: fullName,
            userTextPhoneNumbers: userTextPhoneNumbers,
            phoneNumberNameMap: phoneNumberNameMap,
            parsedPhoneNumbers: parsedPhoneNumbers,
            emails: []
        )
    }
}

// MARK: - Names

public extension Contact {
    static func fullName(
        fromGivenName givenName: String?,
        familyName: String?,
        nickname: String?
    ) -> String? {
        if
            givenName == nil,
            familyName == nil,
            nickname == nil
        {
            return nil
        }

        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName
        components.nickname = nickname

        return PersonNameComponentsFormatter.localizedString(
            from: components,
            style: .default
        )
    }
}
