//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

extension Contact {

    // MARK: - Equality

    public static func areNamesEqual(_ lhs: Contact?, _ rhs: Contact?) -> Bool {
        return lhs === rhs || (
            lhs?.firstName == rhs?.firstName
            && lhs?.lastName == rhs?.lastName
            && lhs?.nickname == rhs?.nickname
            && lhs?.fullName == rhs?.fullName
        )
    }

    // MARK: - Phone Numbers

    public static func uniquePhoneNumberLabel(
        for phoneNumber: CanonicalPhoneNumber,
        relatedPhoneNumbers: [(phoneNumber: CanonicalPhoneNumber, userProvidedLabel: String)]
    ) -> String? {
        guard relatedPhoneNumbers.count > 1 else {
            return nil
        }

        // 1. Find this phone number's type.
        let phoneNumberLabel = relatedPhoneNumbers
            .first(where: { $0.phoneNumber == phoneNumber })?
            .userProvidedLabel
            .filterForDisplay
        guard let phoneNumberLabel else {
            owsFailDebug("Couldn't find phoneNumber in relatedPhoneNumbers")
            return nil
        }

        // 2. Find all phone numbers of this type.
        let phoneNumbersWithTheSameLabel = relatedPhoneNumbers.lazy.filter {
            return phoneNumberLabel == $0.userProvidedLabel.filterForDisplay
        }.map { $0.phoneNumber }.sorted(by: { $0.rawValue.stringValue < $1.rawValue.stringValue })

        // 3. Figure out if this is "Mobile 0" or "Mobile 1".
        guard let thisPhoneNumberIndex = phoneNumbersWithTheSameLabel.firstIndex(of: phoneNumber) else {
            owsFailDebug("Couldn't find the address we were trying to match.")
            return phoneNumberLabel
        }

        // 4. If there's only one "Mobile", don't add the " 0" or " 1" suffix.
        guard phoneNumbersWithTheSameLabel.count > 1 else {
            return phoneNumberLabel
        }

        // 5. If there's two or more "Mobile" numbers, specify which this is.
        let format = OWSLocalizedString(
            "PHONE_NUMBER_TYPE_AND_INDEX_NAME_FORMAT",
            comment: "Format for phone number label with an index. Embeds {{Phone number label (e.g. 'home')}} and {{index, e.g. 2}}."
        )
        return String(format: format, phoneNumberLabel, OWSFormat.formatInt(thisPhoneNumberIndex))
    }

    public convenience init(
        phoneNumber: String,
        phoneNumberLabel: String,
        givenName: String?,
        familyName: String?,
        nickname: String?,
        fullName: String
    ) {
        self.init(
            uniqueId: UUID().uuidString,
            cnContactId: nil,
            firstName: givenName,
            lastName: familyName,
            nickname: nickname,
            fullName: fullName,
            userTextPhoneNumbers: [phoneNumber],
            userTextPhoneNumberLabels: [phoneNumber: phoneNumberLabel],
            emails: []
        )
    }

    // MARK: - Names

    public static func fullName(
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

    /// This method is used to de-bounce system contact fetch notifications by
    /// checking for changes in the contact data.
    func computeSystemContactHashValue() -> Int {
        var hasher = Hasher()
        hasher.combine(cnContactId)
        hasher.combine(firstName)
        hasher.combine(lastName)
        hasher.combine(fullName)
        hasher.combine(nickname)
        hasher.combine(userTextPhoneNumbers)
        // TODO: Include userTextPhoneNumberLabels in a follow-up commit.
        // Don't include "emails" because it doesn't impact system contacts.
        return hasher.finalize()
    }
}
