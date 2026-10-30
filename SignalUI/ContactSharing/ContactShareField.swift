//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol ContactShareField: AnyObject {
    var isIncluded: Bool { get set }
    var localizedLabel: String { get }
    func applyToContact(contact: ContactShareDraft)
}

class ContactShareFieldBase<ContactFieldType: OWSContactField>: ContactShareField {

    let value: ContactFieldType

    init(_ value: ContactFieldType, includedByDefault: Bool = true) {
        self.value = value
        self.isIncludedFlag = includedByDefault
    }

    private var isIncludedFlag: Bool

    var isIncluded: Bool {
        get { isIncludedFlag }
        set { isIncludedFlag = newValue }
    }

    var localizedLabel: String {
        return value.localizedLabel
    }

    func applyToContact(contact: ContactShareDraft) {
        fatalError("applyToContact(contact:) has not been implemented")
    }
}

class ContactSharePhoneNumber: ContactShareFieldBase<OWSContactPhoneNumber> {

    override func applyToContact(contact: ContactShareDraft) {
        owsPrecondition(isIncluded)

        var values = [OWSContactPhoneNumber]()
        values += contact.phoneNumbers
        values.append(value)
        contact.phoneNumbers = values
    }
}

class ContactShareEmail: ContactShareFieldBase<OWSContactEmail> {

    override func applyToContact(contact: ContactShareDraft) {
        owsPrecondition(isIncluded)

        var values = [OWSContactEmail]()
        values += contact.emails
        values.append(value)
        contact.emails = values
    }
}

class ContactShareAddress: ContactShareFieldBase<OWSContactAddress> {

    override func applyToContact(contact: ContactShareDraft) {
        owsPrecondition(isIncluded)

        var values = [OWSContactAddress]()
        values += contact.addresses
        values.append(value)
        contact.addresses = values
    }
}

class OWSContactNickname: OWSContactField {

    let nickname: PersonNameComponents

    init(nickname: PersonNameComponents) {
        self.nickname = nickname
    }

    var isValid: Bool { true }

    var localizedLabel: String { ContactFieldViewHelper.nicknameFieldLabel }
}

class ContactShareNicknameField: ContactShareFieldBase<OWSContactNickname> {

    override func applyToContact(contact: ContactShareDraft) {
        owsPrecondition(isIncluded)

        contact.signalNickname = value.nickname
    }
}

class OWSContactNote: OWSContactField {

    let note: String

    init(note: String) {
        self.note = note
    }

    var isValid: Bool { true }

    var localizedLabel: String { ContactFieldViewHelper.noteFieldLabel }
}

class ContactShareNoteField: ContactShareFieldBase<OWSContactNote> {

    override func applyToContact(contact: ContactShareDraft) {
        owsPrecondition(isIncluded)

        contact.signalNote = value.note
    }
}

struct ContactShareAvatarOption {
    enum Source: CaseIterable {
        case systemContact
        case signal
    }

    let source: Source
    let imageData: Data
    let image: UIImage

    static func localizedVoiceOverName(source: Source?) -> String {
        switch source {
        case .systemContact:
            return OWSLocalizedString(
                "CONTACT_SHARE_AVATAR_SYSTEM_CONTACT_PHOTO",
                comment: "Name of the option to share a contact's photo from the phone's contacts. Read by VoiceOver on the option, and as the current value of the photo row when it's selected.",
            )
        case .signal:
            return OWSLocalizedString(
                "CONTACT_SHARE_AVATAR_SIGNAL_PHOTO",
                comment: "Name of the option to share a contact's Signal profile photo. Read by VoiceOver on the option, and as the current value of the photo row when it's selected.",
            )
        case nil:
            return OWSLocalizedString(
                "CONTACT_SHARE_AVATAR_NO_PHOTO",
                comment: "Name of the option to share a contact without a photo, which shows their initials instead. Read by VoiceOver on the option, and as the current value of the photo row when it's selected.",
            )
        }
    }
}

class ContactShareAvatarField {

    let options: [ContactShareAvatarOption]

    /// `nil` shares no avatar, which recipients see as the contact's initials.
    var selectedSource: ContactShareAvatarOption.Source?

    init?(contactShareDraft: ContactShareDraft, preferContactAvatars: Bool) {
        var options = [ContactShareAvatarOption]()
        for source in ContactShareAvatarOption.Source.allCases {
            let imageData: Data?
            switch source {
            case .systemContact:
                imageData = contactShareDraft.systemContactAvatarImageData
            case .signal:
                imageData = contactShareDraft.signalAvatarImageData
            }
            guard let imageData, !options.contains(where: { $0.imageData == imageData }) else {
                continue
            }
            guard let image = UIImage(data: imageData) else {
                owsFailDebug("could not load avatar image.")
                continue
            }
            options.append(ContactShareAvatarOption(source: source, imageData: imageData, image: image))
        }
        guard let firstOption = options.first else {
            return nil
        }
        self.options = options
        let preferredSource: ContactShareAvatarOption.Source = preferContactAvatars ? .systemContact : .signal
        self.selectedSource = options.contains { $0.source == preferredSource } ? preferredSource : firstOption.source
    }

    var selectedOption: ContactShareAvatarOption? {
        options.first { $0.source == selectedSource }
    }

    func applyToContact(contact: ContactShareDraft) {
        contact.selectedAvatarImageData = selectedOption?.imageData
    }
}
