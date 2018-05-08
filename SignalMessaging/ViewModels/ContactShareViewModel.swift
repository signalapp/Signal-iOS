//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

//@objc
//public protocol BaseContactShareViewModel {
//    func name() -> OWSContactName
//    func phoneNumbers() -> [OWSContactPhoneNumber]
//    func emails() -> [OWSContactEmail]
//    func addresses() -> [OWSContactAddress]
//
//    func avatarData() -> Data?
//    func avatarImage() -> UIImage?
//
//    func systemContactsWithSignalAccountPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String]
//    func systemContactPhoneNumbers(_ contactsManager: ContactsManagerProtocol) -> [String]
//    func e164PhoneNumbers() -> [String]
//}

// MARK: -

@objc
public class ContactShareViewUtils: NSObject {

    @objc
    public class func avatarOrDefaultImage(forContactShareViewModel contactShareViewModel: BaseContactShareViewModel,
                                           diameter: CGFloat,
                                           contactsManager: OWSContactsManager) -> UIImage {
        if let avatarImage = contactShareViewModel.avatarImage() {
            return avatarImage
        }

        var colorSeed = contactShareViewModel.name().displayName
        let recipientIds = contactShareViewModel.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
        if let firstRecipientId = recipientIds.first {
            // Try to use the first signal id as the default
            // avatar's color seed, so that it is as consistent
            // as possible with the user's avatar in other views.
            colorSeed = firstRecipientId
        }

        let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: contactShareViewModel.name().displayName,
                                                    colorSeed: colorSeed,
                                                    diameter: UInt(diameter),
                                                    contactsManager: contactsManager)
        return avatarBuilder.build()
    }
}

// MARK: -

@objc
public class BaseContactShareViewModel: NSObject {

    private let contactShareBase: OWSContactShareBase
    private let avatarDataCached: Data?
    private var avatarImageCached: UIImage?

    init(contactShareBase: OWSContactShareBase, avatarData: Data?, avatarImage: UIImage? = nil) {
        self.contactShareBase = contactShareBase
        self.avatarDataCached = avatarData
        self.avatarImageCached = avatarImage

        super.init()
    }

    public func avatarData() -> Data? {
        return avatarDataCached
    }

    public func avatarImage() -> UIImage? {
        guard let avatarDataCached = avatarDataCached else {
            return nil
        }
        if let avatarImageCached = avatarImageCached {
            return avatarImageCached
        }
        avatarImageCached = UIImage(data: avatarDataCached)
        assert(avatarImageCached != nil)
        return avatarImageCached
    }

    // MARK: -

    public func name() -> OWSContactName {
        return contactShareBase.name
    }

    public func phoneNumbers() -> [OWSContactPhoneNumber] {
        return contactShareBase.phoneNumbers
    }

    public func emails() -> [OWSContactEmail] {
        return contactShareBase.emails
    }

    public func addresses() -> [OWSContactAddress] {
        return contactShareBase.addresses
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

    public func displayName() -> String {
        return contactShareBase.name.displayName
    }

    public func ows_isValid() -> Bool {
        return contactShareBase.ows_isValid()
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
                owsFail("\(ContactShareViewModel.logTag) \(#function) failed to load attachment data with error: \(error)")
            }
        }

        super.init(contactShareBase: contactShare, avatarData: avatarData)
    }

    // MARK : -

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

        return ProposedContactShareViewModel(contactShare: contactShareCopy, avatarImage: avatarImage())
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

        newContactShare.name = contactShare.name.copy() as! OWSContactName
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
