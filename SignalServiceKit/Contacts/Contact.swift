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
        userProvidedLabel: String,
        discoverablePhoneNumberCount: Int
    ) -> String? {
        // If there's only one phone number for this contact, don't show the label.
        if discoverablePhoneNumberCount <= 1 {
            return nil
        } else {
            return userProvidedLabel.filterForDisplay
        }
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
}
