//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

// MARK: - Convenience init

public extension Contact {
    convenience init(
        address: SignalServiceAddress,
        addressServiceIdentifier: String,
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
            uniqueId: addressServiceIdentifier,
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
