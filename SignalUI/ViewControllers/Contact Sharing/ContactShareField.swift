//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol ContactShareField: AnyObject {
    var isIncluded: Bool { get set }
    var localizedLabel: String { get }
    func applyToContact(contact: ContactShareViewModel)
}

class ContactShareFieldBase<ContactFieldType: OWSContactField>: ContactShareField {

    let value: ContactFieldType

    required init(_ value: ContactFieldType) {
        self.value = value
    }

    private var isIncludedFlag = true

    var isIncluded: Bool {
        get { isIncludedFlag }
        set { isIncludedFlag = newValue }
    }

    var localizedLabel: String {
        return value.localizedLabel
    }

    func applyToContact(contact: ContactShareViewModel) {
        fatalError("applyToContact(contact:) has not been implemented")
    }
}

class ContactSharePhoneNumber: ContactShareFieldBase<OWSContactPhoneNumber> {

    override func applyToContact(contact: ContactShareViewModel) {
        owsAssert(isIncluded)

        var values = [OWSContactPhoneNumber]()
        values += contact.phoneNumbers
        values.append(value)
        contact.phoneNumbers = values
    }
}

class ContactShareEmail: ContactShareFieldBase<OWSContactEmail> {

    override func applyToContact(contact: ContactShareViewModel) {
        owsAssert(isIncluded)

        var values = [OWSContactEmail]()
        values += contact.emails
        values.append(value)
        contact.emails = values
    }
}

class ContactShareAddress: ContactShareFieldBase<OWSContactAddress> {

    override func applyToContact(contact: ContactShareViewModel) {
        owsAssert(isIncluded)

        var values = [OWSContactAddress]()
        values += contact.addresses
        values.append(value)
        contact.addresses = values
    }
}

// Stub class so that avatars conform to OWSContactField.
class OWSContactAvatar: NSObject, OWSContactField {

    let avatarImage: UIImage
    let avatarData: Data

    required init(avatarImage: UIImage, avatarData: Data) {
        self.avatarImage = avatarImage
        self.avatarData = avatarData

        super.init()
    }

    var isValid: Bool { true }

    var localizedLabel: String { "" }
}

class ContactShareAvatarField: ContactShareFieldBase<OWSContactAvatar> {

    override func applyToContact(contact: ContactShareViewModel) {
        owsAssert(isIncluded)

        contact.avatarImageData = value.avatarData
    }
}
