//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class BaseContactShareViewModel: NSObject {

    private let contactShareBase: OWSContactShareBase
    public let avatarData: Data?
    private var avatarImageCached: UIImage?

    init(contactShareBase: OWSContactShareBase, avatarData: Data?, avatarImage: UIImage? = nil) {
        self.contactShareBase = contactShareBase
        self.avatarData = avatarData
        self.avatarImageCached = avatarImage

        super.init()
    }

    public var avatarImage: UIImage? {
        get {
            guard let avatarDataCached = avatarData else {
                return nil
            }
            if let avatarImageCached = avatarImageCached {
                return avatarImageCached
            }
            avatarImageCached = UIImage(data: avatarDataCached)
            assert(avatarImageCached != nil)
            return avatarImageCached
        }
    }

    // MARK: -

    public var name: OWSContactName {
        get {
            return contactShareBase.name
        }
    }

    public var phoneNumbers: [OWSContactPhoneNumber] {
        get {
            return contactShareBase.phoneNumbers
        }
    }

    public var emails: [OWSContactEmail] {
        get {
            return contactShareBase.emails
        }
    }

    public var addresses: [OWSContactAddress] {
        get {
            return contactShareBase.addresses
        }
    }

    public var displayName: String {
        get {
            return contactShareBase.name.displayName
        }
    }

    public var ows_isValid: Bool {
        get {
            return contactShareBase.ows_isValid()
        }
    }

    public func systemContactsWithSignalAccountPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String] {
        return contactShareBase.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
    }

    public func systemContactPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String] {
        return contactShareBase.systemContactPhoneNumbers(contactsManager)
    }

    public func e164PhoneNumbers() -> [String] {
        return contactShareBase.e164PhoneNumbers()
    }

    public func avatarOrDefaultImage(diameter: CGFloat,
                                     contactsManager: OWSContactsManager) -> UIImage {
        if let avatarImage = avatarImage {
            return avatarImage
        }

        var colorSeed = name.displayName
        let recipientIds = systemContactsWithSignalAccountPhoneNumbers(contactsManager)
        if let firstRecipientId = recipientIds.first {
            // Try to use the first signal id as the default
            // avatar's color seed, so that it is as consistent
            // as possible with the user's avatar in other views.
            colorSeed = firstRecipientId
        }

        let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: name.displayName,
                                                    colorSeed: colorSeed,
                                                    diameter: UInt(diameter),
                                                    contactsManager: contactsManager)
        return avatarBuilder.build()
    }
}

// MARK: -

// Immutable view model for contact shares.
@objc
public class ContactShareViewModel: BaseContactShareViewModel {

    private let contactShare: OWSContactShare

    public init(contactShare: OWSContactShare, avatarData: Data?, avatarImage: UIImage? = nil) {
        self.contactShare = contactShare

        super.init(contactShareBase: contactShare, avatarData: avatarData, avatarImage: avatarImage)
    }

    public init(contactShare: OWSContactShare, transaction: YapDatabaseReadTransaction) {
        self.contactShare = contactShare

        var avatarData: Data?
        if let avatarAttachment = contactShare.avatarAttachment(with: transaction) as? TSAttachmentStream {
            do {
                try avatarData = avatarAttachment.readDataFromFile()
            } catch {
                owsFail("\(ContactShareViewModel.logTag) \(#function) failed to load with error: \(error)")
            }
        }

        super.init(contactShareBase: contactShare, avatarData: avatarData)
    }

    // MARK: -

    public func convertToSystemContact(transaction: YapDatabaseReadTransaction) -> CNContact? {
        return OWSContactConversion.systemContact(for: contactShare, transaction: transaction)
    }
}

// MARK: -

@objc
public class ProposedContactShareViewModel: BaseContactShareViewModel {

    private let contactShare: OWSContactShareProposed

    public init(contactShare: OWSContactShareProposed, avatarImage: UIImage? = nil) {
        self.contactShare = contactShare

        super.init(contactShareBase: contactShare, avatarData: contactShare.avatarData, avatarImage: avatarImage)
    }

    public required init(contactShare: OWSContactShareProposed) {
        self.contactShare = contactShare

        super.init(contactShareBase: contactShare, avatarData: contactShare.avatarData)
    }

    // MARK: -

    public func copy(withName name: OWSContactName) -> ProposedContactShareViewModel? {
        guard let contactShareCopy = contactShare.copy() as? OWSContactShareProposed else {
            return nil
        }

        contactShareCopy.name = name

        return ProposedContactShareViewModel(contactShare: contactShareCopy, avatarImage: avatarImage)
    }

    public func newProposedContactShare(withName name: OWSContactName) -> OWSContactShareProposed? {
        guard let newContactShare = OWSContactShareProposed() else {
            return nil
        }

        newContactShare.name = name

        return newContactShare
    }

    public func convertForSending(transaction: YapDatabaseReadWriteTransaction) -> OWSContactShare? {
        guard let newContactShare = OWSContactShare() else {
            return nil
        }

        guard let nameCopy = contactShare.name.copy() as? OWSContactName else {
            return nil
        }

        newContactShare.name = nameCopy
        newContactShare.phoneNumbers = contactShare.phoneNumbers
        newContactShare.emails = contactShare.emails
        newContactShare.addresses = contactShare.addresses
        newContactShare.isProfileAvatar = contactShare.isProfileAvatar

        if let avatarData = contactShare.avatarData {
            newContactShare.saveAvatarData(avatarData, transaction: transaction)
        }

        return newContactShare
    }
}
