//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactName)
public class OWSContactName: MTLModel {

    @objc
    public fileprivate(set) var givenName: String?
    @objc
    public fileprivate(set) var familyName: String?
    @objc
    public fileprivate(set) var namePrefix: String?
    @objc
    public fileprivate(set) var nameSuffix: String?
    @objc
    public fileprivate(set) var middleName: String?
    @objc
    public fileprivate(set) var nickname: String?
    @objc
    public fileprivate(set) var organizationName: String?

    public override init() {
        super.init()
    }

    public init(
        givenName: String? = nil,
        familyName: String? = nil,
        namePrefix: String? = nil,
        nameSuffix: String? = nil,
        middleName: String? = nil,
        nickname: String? = nil,
        organizationName: String? = nil
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.namePrefix = namePrefix
        self.nameSuffix = nameSuffix
        self.middleName = middleName
        self.nickname = nickname
        self.organizationName = organizationName
        super.init()
    }

    public convenience init(cnContact: CNContact) {
        // Name
        self.init(
            givenName: cnContact.givenName.stripped,
            familyName: cnContact.familyName.stripped,
            namePrefix: cnContact.namePrefix.stripped,
            nameSuffix: cnContact.nameSuffix.stripped,
            middleName: cnContact.middleName.stripped,
            nickname: cnContact.nickname.stripped,
            organizationName: cnContact.organizationName.stripped
        )
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: Display Name

    private var _displayName: String?

    @objc
    public var displayName: String {
        ensureDisplayName()

        guard let displayName = _displayName?.nilIfEmpty else {
            owsFailDebug("could not derive a valid display name.")
            return OWSLocalizedString("CONTACT_WITHOUT_NAME", comment: "Indicates that a contact has no name.")
        }

        return displayName
    }

    internal func ensureDisplayName() {
        if _displayName.isEmptyOrNil {
            if let cnContact = systemContactForName() {
                if let nickname = cnContact.nickname.nilIfEmpty {
                    _displayName = nickname
                } else {
                    _displayName = CNContactFormatter.string(from: cnContact, style: .fullName)
                }
            }
        }

        if _displayName.isEmptyOrNil {
            if let nickname = nickname?.nilIfEmpty {
                _displayName = nickname
            } else {
                // Fall back to using the organization name.
                _displayName = organizationName
            }
        }
    }

    internal func updateDisplayName() {
        _displayName = nil
        ensureDisplayName()
    }

    private func systemContactForName() -> CNContact? {
        let cnContact = CNMutableContact()
        cnContact.givenName = givenName?.stripped ?? ""
        cnContact.middleName = middleName?.stripped ?? ""
        cnContact.familyName = familyName?.stripped ?? ""
        cnContact.namePrefix = namePrefix?.stripped ?? ""
        cnContact.nameSuffix = nameSuffix?.stripped ?? ""
        cnContact.nickname = nickname?.stripped ?? ""
        cnContact.organizationName = organizationName?.stripped ?? ""
        // We don't need to set display name, it's implicit for system contacts.
        return cnContact
    }

    // Returns true if any of the name parts (which doesn't include
    // organization name) is non-empty.
    public var hasAnyNamePart: Bool {
        let components: [String?] = [ givenName, middleName, familyName, namePrefix, nameSuffix, nickname ]
        for component in components {
            if component?.strippedOrNil != nil {
                return true
            }
        }
        return false
    }

    public var components: PersonNameComponents {
        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName
        components.middleName = middleName
        components.namePrefix = namePrefix
        components.nameSuffix = nameSuffix
        components.nickname = nickname
        return components
    }
}
