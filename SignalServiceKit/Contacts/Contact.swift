//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(Contact)
public class Contact: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let cnContactId: String?
    public let firstName: String
    public let lastName: String
    public let nickname: String
    public let fullName: String
    public var isFromLocalAddressBook: Bool { cnContactId != nil }

    public init(cnContactId: String?, firstName: String, lastName: String, nickname: String, fullName: String) {
        self.cnContactId = cnContactId
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.fullName = fullName
    }

    public required init?(coder: NSCoder) {
        self.cnContactId = coder.decodeObject(of: NSString.self, forKey: "cnContactId") as String?
        self.firstName = coder.decodeObject(of: NSString.self, forKey: "firstName") as String? ?? ""
        self.lastName = coder.decodeObject(of: NSString.self, forKey: "lastName") as String? ?? ""
        self.fullName = coder.decodeObject(of: NSString.self, forKey: "fullName") as String? ?? ""
        self.nickname = coder.decodeObject(of: NSString.self, forKey: "nickname") as String? ?? ""
    }

    public func encode(with coder: NSCoder) {
        coder.encode(cnContactId, forKey: "cnContactId")
        coder.encode(firstName, forKey: "firstName")
        coder.encode(lastName, forKey: "lastName")
        coder.encode(fullName, forKey: "fullName")
        coder.encode(nickname, forKey: "nickname")
    }
}

extension Contact {

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
