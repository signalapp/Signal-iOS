//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
public import SignalServiceKit

public class ContactShareViewModel: NSObject {

    public let dbRecord: OWSContact

    private let existingAvatarAttachment: ReferencedAttachment?

    public var avatarImageData: Data? {
        didSet {
            self.cachedAvatarImage = nil
        }
    }

    private var cachedAvatarImage: UIImage?

    public var avatarImage: UIImage? {
        if self.cachedAvatarImage != nil {
            return self.cachedAvatarImage
        }

        guard let avatarImageData = self.avatarImageData else {
            return nil
        }

        self.cachedAvatarImage = UIImage(data: avatarImageData)
        return cachedAvatarImage
    }

    private init(
        contactShareRecord: OWSContact,
        existingAvatarAttachment: ReferencedAttachment?,
        avatarImageData: Data?
    ) {
        self.dbRecord = contactShareRecord
        self.existingAvatarAttachment = existingAvatarAttachment
        self.avatarImageData = avatarImageData
    }

    public convenience init(
        contactShareRecord: OWSContact,
        parentMessage: TSMessage,
        transaction: SDSAnyReadTransaction
    ) {
        if
            let parentMessageRowId = parentMessage.sqliteRowId,
            let avatarAttachment = DependenciesBridge.shared.attachmentStore.fetchFirstReferencedAttachment(
                for: .messageContactAvatar(messageRowId: parentMessageRowId),
                tx: transaction.asV2Read
            )?.asReferencedStream
        {
            let avatarImageData: Data?
            switch avatarAttachment.attachmentStream.contentType {
            case .file, .invalid, .video, .animatedImage, .audio:
                avatarImageData = nil
            case .image:
                avatarImageData = try? avatarAttachment.attachmentStream.decryptedRawData()
            }
            self.init(
                contactShareRecord: contactShareRecord,
                existingAvatarAttachment: avatarAttachment,
                avatarImageData: avatarImageData
            )
        } else {
            self.init(
                contactShareRecord: contactShareRecord,
                existingAvatarAttachment: nil,
                avatarImageData: nil
            )
        }
    }

    public func getAvatarImageWithSneakyTransaction(diameter: CGFloat) -> UIImage? {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.getAvatarImage(diameter: diameter, transaction: transaction)
        }
    }

    public func getAvatarImage(diameter: CGFloat, transaction: SDSAnyReadTransaction) -> UIImage? {
        if let avatarImage = avatarImage {
            return avatarImage
        }

        // Note: We build an avatar that _never_ reflects the name,
        // not any corresponding system contact or profile.
        // This could mislead the user into thinking
        // that an avatar they did not share was in fact included in the
        // contact share.
        return SSKEnvironment.shared.avatarBuilderRef.avatarImage(
            personNameComponents: name.components,
            diameterPoints: UInt(diameter),
            transaction: transaction
        )
    }

    // MARK: Delegated -> dbRecord

    public var name: OWSContactName {
        get {
            return dbRecord.name
        }
        set {
            return dbRecord.name = newValue
        }
    }

    public var addresses: [OWSContactAddress] {
        get {
            return dbRecord.addresses
        }
        set {
            return dbRecord.addresses = newValue
        }
    }

    public var emails: [OWSContactEmail] {
        get {
            return dbRecord.emails
        }
        set {
            dbRecord.emails = newValue
        }
    }

    public var phoneNumbers: [OWSContactPhoneNumber] {
        get {
            return dbRecord.phoneNumbers
        }
        set {
            dbRecord.phoneNumbers = newValue
        }
    }

    public var displayName: String {
        return dbRecord.name.displayName
    }

    public func copyForResending() -> ContactShareDraft {
        return ContactShareDraft(
            name: name,
            addresses: addresses,
            emails: emails,
            phoneNumbers: phoneNumbers,
            existingAvatarAttachment: existingAvatarAttachment,
            avatarImageData: avatarImageData
        )
    }

    public func copyForRendering() -> ContactShareViewModel {
        let newDbRecord = dbRecord.copy() as! OWSContact
        return ContactShareViewModel(
            contactShareRecord: newDbRecord,
            existingAvatarAttachment: existingAvatarAttachment,
            avatarImageData: avatarImageData
        )
    }
}
