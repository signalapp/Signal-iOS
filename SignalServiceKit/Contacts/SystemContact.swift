//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
import Foundation

public struct SystemContact {
    private enum Constants {
        static let maxPhoneNumbers = 50
    }

    public let cnContactId: String
    public let firstName: String
    public let lastName: String
    public let nickname: String
    public let fullName: String
    public let phoneNumbers: [(value: String, label: String?)]
    public let emailAddresses: [String]

    public init(cnContact: CNContact, didFetchEmailAddresses: Bool = true) {
        if cnContact.phoneNumbers.count > Constants.maxPhoneNumbers {
            Logger.warn("Ignoring phone numbers from contact with more than \(Constants.maxPhoneNumbers)")
        }

        var phoneNumbers = [(String, String?)]()
        for phoneNumber in cnContact.phoneNumbers.prefix(Constants.maxPhoneNumbers) {
            phoneNumbers.append((
                phoneNumber.value.stringValue,
                Self.inAppLocalizedString(forCNLabel: phoneNumber.label)
            ))
        }

        var emailAddresses = [String]()
        if didFetchEmailAddresses {
            for emailAddress in cnContact.emailAddresses {
                emailAddresses.append(emailAddress.value as String)
            }
        }

        self.cnContactId = cnContact.identifier
        self.firstName = cnContact.givenName.stripped
        self.lastName = cnContact.familyName.stripped
        self.nickname = cnContact.nickname.stripped
        self.fullName = Self.formattedFullName(for: cnContact)
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
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
        hasher.combine(phoneNumbers.map { $0.value })
        hasher.combine(phoneNumbers.map { $0.label })
        // Don't include "emails" because it doesn't impact system contacts.
        return hasher.finalize()
    }

    // MARK: - Avatars

    static func avatarData(for cnContact: CNContact) -> Data? {
        // We only use `imageData` when sharing from the share extension.
        return cnContact.thumbnailImageData ?? cnContact.imageData
    }

    // MARK: - vCards

    public static func parseVCardData(_ vCardData: Data) throws -> CNContact {
        let cnContacts = try CNContactVCardSerialization.contacts(with: vCardData)
        guard let cnContact = cnContacts.first else {
            throw OWSGenericError("vCard had no contacts")
        }
        guard cnContacts.count == 1 else {
            throw OWSGenericError("vCard had more than one contact")
        }
        return cnContact
    }

    // MARK: - Labels

    private static func inAppLocalizedString(forCNLabel cnLabel: String?) -> String? {
        switch cnLabel {
        case CNLabelHome:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_HOME", comment: "Label for 'Home' phone numbers.")
        case CNLabelWork:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_WORK", comment: "Label for 'Work' phone numbers.")
        case CNLabelPhoneNumberiPhone:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_IPHONE", comment: "Label for 'iPhone' phone numbers.")
        case CNLabelPhoneNumberMobile:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_MOBILE", comment: "Label for 'Mobile' phone numbers.")
        case CNLabelPhoneNumberMain:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_MAIN", comment: "Label for 'Main' phone numbers.")
        case CNLabelPhoneNumberHomeFax:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_HOME_FAX", comment: "Label for 'HomeFAX' phone numbers.")
        case CNLabelPhoneNumberWorkFax:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_WORK_FAX", comment: "Label for 'Work FAX' phone numbers.")
        case CNLabelPhoneNumberOtherFax:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_OTHER_FAX", comment: "Label for 'Other FAX' phone numbers.")
        case CNLabelPhoneNumberPager:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_PAGER", comment: "Label for 'Pager' phone numbers.")
        case CNLabelOther:
            return OWSLocalizedString("PHONE_NUMBER_TYPE_OTHER", comment: "Label for 'Other' phone numbers.")
        case .some(let cnLabel) where cnLabel.hasPrefix("_$"):
            // We'll reach this case for labels like "_$!<CompanyMain>!$_", which I'm
            // guessing are synced from other platforms. We don't want to display these
            // labels. Even some of iOS' default labels (like Radio) show up this way.
            return nil
        default:
            // We'll reach this case for user-defined custom labels.
            return cnLabel?.nilIfEmpty
        }
    }

    public static func localizedString<T>(
        forCNLabel cnLabel: String?,
        labeledValueType: CNLabeledValue<T>.Type
    ) -> String? {
        guard let cnLabel = cnLabel?.nilIfEmpty else {
            return nil
        }

        let localizedLabel = labeledValueType.localizedString(forLabel: cnLabel)

        // TODO: Check if this is still broken on iOS versions after iOS 11.
        // It's supposed to return the label or a localized value, never this.
        if localizedLabel == "__ABUNLOCALIZEDSTRING" {
            return cnLabel
        }

        return localizedLabel
    }

    // MARK: -

    public static func formattedFullName(for cnContact: CNContact) -> String {
        return CNContactFormatter.string(from: cnContact, style: .fullName)?.stripped ?? ""
    }
}
