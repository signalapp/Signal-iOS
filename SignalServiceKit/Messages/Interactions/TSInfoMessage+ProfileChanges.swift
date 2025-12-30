//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSInfoMessage {
    class func insertProfileChangeMessagesIfNecessary(
        oldProfile: OWSUserProfile,
        newProfile: OWSUserProfile,
        transaction: DBWriteTransaction,
    ) {
        let address: SignalServiceAddress
        switch oldProfile.internalAddress {
        case .localUser:
            return
        case .otherUser(let otherUserAddress):
            address = otherUserAddress
        }

        let profileChanges = ProfileChanges(
            address: address,
            oldProfile: oldProfile,
            newProfile: newProfile,
        )

        guard profileChanges.hasRenderableChanges else {
            return
        }

        func saveProfileUpdateMessage(thread: TSThread) {
            let profileUpdateMessage: TSInfoMessage = .makeForProfileChange(
                thread: thread,
                profileChanges: profileChanges,
            )
            profileUpdateMessage.anyInsert(transaction: transaction)
        }

        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        if contactThread.shouldThreadBeVisible {
            saveProfileUpdateMessage(thread: contactThread)
        }

        for groupThread in TSGroupThread.groupThreads(with: address, transaction: transaction) {
            guard groupThread.groupModel.groupMembership.isLocalUserFullMember, groupThread.shouldThreadBeVisible else {
                continue
            }
            saveProfileUpdateMessage(thread: groupThread)
        }
    }

    static func makeForProfileChange(
        thread: TSThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        profileChanges: ProfileChanges,
    ) -> TSInfoMessage {
        let infoMessage = TSInfoMessage(
            thread: thread,
            messageType: .profileUpdate,
            timestamp: timestamp,
            infoMessageUserInfo: [.profileChanges: profileChanges],
        )
        infoMessage.wasRead = true

        return infoMessage
    }
}

// MARK: -

public extension TSInfoMessage {
    @objc
    func profileChangeDescription(transaction tx: DBReadTransaction) -> String {
        guard
            let profileChanges,
            let updateDescription = profileChanges.descriptionForUpdate(tx: tx)
        else {
            owsFailDebug("Unexpectedly missing update description for profile change")
            return ""
        }

        return updateDescription
    }

    var profileChangeAddress: SignalServiceAddress? {
        return profileChanges?.address
    }

    var profileChangesOldFullName: String? {
        profileChanges?.oldFullName
    }

    var profileChangesNewFullName: String? {
        profileChanges?.newFullName
    }

    var profileChangesNewNameComponents: PersonNameComponents? {
        if let newNameComponents = profileChanges?.newNameComponents {
            return newNameComponents
        } else if let newNameLiteral = profileChanges?.newNameLiteral {
            /// If we only have the literal new name, we can use it to seed a
            /// `PersonNameComponents`. This isn't ideal, but better than `nil`.
            ///
            /// (At the time of writing, this would only happen for a profile
            /// change update that was restored from a Backup.)
            return PersonNameComponents(givenName: newNameLiteral)
        }

        return nil
    }

    private var profileChanges: ProfileChanges? {
        return infoMessageUserInfo?[.profileChanges] as? ProfileChanges
    }
}

// MARK: -

/// Represents a profile change for in-chat messages.
public final class ProfileChanges: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.address = coder.decodeObject(of: SignalServiceAddress.self, forKey: "address")
        self.newNameComponents = coder.decodeObject(of: NSPersonNameComponents.self, forKey: "newNameComponents") as PersonNameComponents?
        self.newNameLiteral = coder.decodeObject(of: NSString.self, forKey: "newNameLiteral") as String?
        self.oldNameComponents = coder.decodeObject(of: NSPersonNameComponents.self, forKey: "oldNameComponents") as PersonNameComponents?
        self.oldNameLiteral = coder.decodeObject(of: NSString.self, forKey: "oldNameLiteral") as String?
    }

    public func encode(with coder: NSCoder) {
        if let address {
            coder.encode(address, forKey: "address")
        }
        if let newNameComponents {
            coder.encode(newNameComponents, forKey: "newNameComponents")
        }
        if let newNameLiteral {
            coder.encode(newNameLiteral, forKey: "newNameLiteral")
        }
        if let oldNameComponents {
            coder.encode(oldNameComponents, forKey: "oldNameComponents")
        }
        if let oldNameLiteral {
            coder.encode(oldNameLiteral, forKey: "oldNameLiteral")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(address)
        hasher.combine(newNameComponents)
        hasher.combine(newNameLiteral)
        hasher.combine(oldNameComponents)
        hasher.combine(oldNameLiteral)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.address == object.address else { return false }
        guard self.newNameComponents == object.newNameComponents else { return false }
        guard self.newNameLiteral == object.newNameLiteral else { return false }
        guard self.oldNameComponents == object.oldNameComponents else { return false }
        guard self.oldNameLiteral == object.oldNameLiteral else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    let address: SignalServiceAddress?

    /// If this is populated, `oldNameComponents` will be nil.
    let oldNameLiteral: String?
    /// If this is populated, `oldNameLiteral` will be nil.
    let oldNameComponents: PersonNameComponents?

    /// If this is populated, `newNameComponents` will be nil.
    let newNameLiteral: String?
    /// If this is populated, `newNameLiteral` will be nil.
    let newNameComponents: PersonNameComponents?

    var oldFullName: String? {
        if let oldNameLiteral {
            return oldNameLiteral
        } else if let oldNameComponents {
            return OWSFormat.formatNameComponents(oldNameComponents).filterStringForDisplay()
        }

        return nil
    }

    var newFullName: String? {
        if let newNameLiteral {
            return newNameLiteral
        } else if let newNameComponents {
            return OWSFormat.formatNameComponents(newNameComponents).filterStringForDisplay()
        }

        return nil
    }

    var hasRenderableChanges: Bool {
        return oldFullName != nil && newFullName != nil && oldFullName != newFullName
    }

    init(address: SignalServiceAddress, oldNameLiteral: String, newNameLiteral: String) {
        self.address = address
        self.oldNameComponents = nil
        self.oldNameLiteral = oldNameLiteral
        self.newNameComponents = nil
        self.newNameLiteral = newNameLiteral

        super.init()
    }

    init(address: SignalServiceAddress, oldProfile: OWSUserProfile, newProfile: OWSUserProfile) {
        self.address = address
        self.oldNameComponents = oldProfile.filteredNameComponents
        self.oldNameLiteral = nil
        self.newNameComponents = newProfile.filteredNameComponents
        self.newNameLiteral = nil

        super.init()
    }

    func descriptionForUpdate(tx: DBReadTransaction) -> String? {
        guard let address else {
            owsFailDebug("Unexpectedly missing address for profile change")
            return nil
        }

        guard let oldFullName = oldFullName?.filterForDisplay, let newFullName = newFullName?.filterForDisplay else {
            owsFailDebug("Unexpectedly missing old and new full name")
            return nil
        }

        if let phoneNumber = address.phoneNumber, let systemContactName = SSKEnvironment.shared.contactManagerRef.systemContactName(for: phoneNumber, tx: tx) {
            let formatString = OWSLocalizedString(
                "PROFILE_NAME_CHANGE_SYSTEM_CONTACT_FORMAT",
                comment: "The copy rendered in a conversation when someone in your address book changes their profile name. Embeds {contact name}, {old profile name}, {new profile name}",
            )
            return String(format: formatString, systemContactName.resolvedValue(), oldFullName, newFullName)
        } else {
            let formatString = OWSLocalizedString(
                "PROFILE_NAME_CHANGE_SYSTEM_NONCONTACT_FORMAT",
                comment: "The copy rendered in a conversation when someone not in your address book changes their profile name. Embeds {old profile name}, {new profile name}",
            )
            return String(format: formatString, oldFullName, newFullName)
        }
    }
}
