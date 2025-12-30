//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactName)
public final class OWSContactName: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.familyName = coder.decodeObject(of: NSString.self, forKey: "familyName") as String?
        self.givenName = coder.decodeObject(of: NSString.self, forKey: "givenName") as String?
        self.middleName = coder.decodeObject(of: NSString.self, forKey: "middleName") as String?
        self.namePrefix = coder.decodeObject(of: NSString.self, forKey: "namePrefix") as String?
        self.nameSuffix = coder.decodeObject(of: NSString.self, forKey: "nameSuffix") as String?
        self.nickname = coder.decodeObject(of: NSString.self, forKey: "nickname") as String?
        self.organizationName = coder.decodeObject(of: NSString.self, forKey: "organizationName") as String?
    }

    public func encode(with coder: NSCoder) {
        if let familyName {
            coder.encode(familyName, forKey: "familyName")
        }
        if let givenName {
            coder.encode(givenName, forKey: "givenName")
        }
        if let middleName {
            coder.encode(middleName, forKey: "middleName")
        }
        if let namePrefix {
            coder.encode(namePrefix, forKey: "namePrefix")
        }
        if let nameSuffix {
            coder.encode(nameSuffix, forKey: "nameSuffix")
        }
        if let nickname {
            coder.encode(nickname, forKey: "nickname")
        }
        if let organizationName {
            coder.encode(organizationName, forKey: "organizationName")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(familyName)
        hasher.combine(givenName)
        hasher.combine(middleName)
        hasher.combine(namePrefix)
        hasher.combine(nameSuffix)
        hasher.combine(nickname)
        hasher.combine(organizationName)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.familyName == object.familyName else { return false }
        guard self.givenName == object.givenName else { return false }
        guard self.middleName == object.middleName else { return false }
        guard self.namePrefix == object.namePrefix else { return false }
        guard self.nameSuffix == object.nameSuffix else { return false }
        guard self.nickname == object.nickname else { return false }
        guard self.organizationName == object.organizationName else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            givenName: givenName,
            familyName: familyName,
            namePrefix: namePrefix,
            nameSuffix: nameSuffix,
            middleName: middleName,
            nickname: nickname,
            organizationName: organizationName,
        )
    }

    public let givenName: String?
    public let familyName: String?
    public let namePrefix: String?
    public let nameSuffix: String?
    public let middleName: String?
    public let nickname: String?
    public let organizationName: String?

    public init(
        givenName: String? = nil,
        familyName: String? = nil,
        namePrefix: String? = nil,
        nameSuffix: String? = nil,
        middleName: String? = nil,
        nickname: String? = nil,
        organizationName: String? = nil,
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
            organizationName: cnContact.organizationName.stripped,
        )
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

    func ensureDisplayName() {
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

    func updateDisplayName() {
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
        let components: [String?] = [givenName, middleName, familyName, namePrefix, nameSuffix, nickname]
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
