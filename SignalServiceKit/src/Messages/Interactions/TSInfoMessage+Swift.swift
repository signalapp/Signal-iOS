//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSInfoMessage {

    // MARK: - Dependencies

    private var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    func groupUpdateDescription(transaction: SDSAnyReadTransaction) -> String {
        // for legacy group updates we persisted a pre-rendered string, rather than the details
        // to generate that string
        if let customMessage = self.customMessage {
            return customMessage
        }

        guard let newGroupModel = self.newGroupModel else {
            // Legacy info message before we began embedding user info.
            return GroupUpdateCopy.defaultGroupUpdateDescription(groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                 transaction: transaction)
        }

        return groupUpdateDescription(oldGroupModel: self.oldGroupModel,
                                      newGroupModel: newGroupModel,
                                      transaction: transaction)
    }

    func groupUpdateItems(transaction: SDSAnyReadTransaction) -> [GroupUpdateCopyItem]? {
        // for legacy group updates we persisted a pre-rendered string, rather than the details
        // to generate that string
        guard customMessage == nil else { return nil }

        guard let newGroupModel = self.newGroupModel else {
            // Legacy info message before we began embedding user info.
            return nil
        }

        return groupUpdateItems(oldGroupModel: self.oldGroupModel,
                                newGroupModel: newGroupModel,
                                transaction: transaction)
    }

    func profileChangeDescription(transaction: SDSAnyReadTransaction) -> String {
        guard let profileChanges = profileChanges,
            let updateDescription = profileChanges.descriptionForUpdate(transaction: transaction) else {
                owsFailDebug("Unexpectedly missing update description for profile change")
            return ""
        }

        return updateDescription
    }

    var profileChangeAddress: SignalServiceAddress? {
        return profileChanges?.address
    }

    var profileChangeNewNameComponents: PersonNameComponents? {
        return profileChanges?.newNameComponents
    }
}

// MARK: -

extension TSInfoMessage {
    private func groupUpdateDescription(oldGroupModel: TSGroupModel?,
                                        newGroupModel: TSGroupModel,
                                        transaction: SDSAnyReadTransaction) -> String {

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return GroupUpdateCopy.defaultGroupUpdateDescription(groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                 transaction: transaction)
        }

        let groupUpdate = GroupUpdateCopy(newGroupModel: newGroupModel,
                                          oldGroupModel: oldGroupModel,
                                          oldDisappearingMessageToken: oldDisappearingMessageToken,
                                          newDisappearingMessageToken: newDisappearingMessageToken,
                                          localAddress: localAddress,
                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                          transaction: transaction)
        return groupUpdate.updateDescription
    }

    private func groupUpdateItems(oldGroupModel: TSGroupModel?,
                                  newGroupModel: TSGroupModel,
                                  transaction: SDSAnyReadTransaction) -> [GroupUpdateCopyItem]? {

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        let groupUpdate = GroupUpdateCopy(newGroupModel: newGroupModel,
                                          oldGroupModel: oldGroupModel,
                                          oldDisappearingMessageToken: oldDisappearingMessageToken,
                                          newDisappearingMessageToken: newDisappearingMessageToken,
                                          localAddress: localAddress,
                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                          transaction: transaction)
        return groupUpdate.itemList
    }

    @objc
    public static func legacyDisappearingMessageUpdateDescription(token newToken: DisappearingMessageToken,
                                                                  wasAddedToExistingGroup: Bool,
                                                                  updaterName: String?) -> String {

        // This might be zero if DMs are not enabled.
        let durationString = newToken.durationString

        if wasAddedToExistingGroup {
            assert(newToken.isEnabled)
            let format = NSLocalizedString("DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
                                           comment: "Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
            return String(format: format, durationString)
        } else if let updaterName = updaterName {
            if newToken.isEnabled {
                let format = NSLocalizedString("OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                return String(format: format, updaterName, durationString)
            } else {
                let format = NSLocalizedString("OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}.")
                return String(format: format, updaterName)
            }
        } else {
            // Changed by localNumber on this device or via synced transcript
            if newToken.isEnabled {
                let format = NSLocalizedString("YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when you update disappearing messages duration. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                return String(format: format, durationString)
            } else {
                return NSLocalizedString("YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                         comment: "Info Message when you disabled disappearing messages.")
            }
        }
    }
}

// MARK: -

extension TSInfoMessage {

    private func infoMessageValue<T>(forKey key: InfoMessageUserInfoKey) -> T? {
        guard let infoMessageUserInfo = self.infoMessageUserInfo else {
            return nil
        }

        guard let groupModel = infoMessageUserInfo[key] as? T else {
            assert(infoMessageUserInfo[key] == nil)
            return nil
        }

        return groupModel
    }

    @objc
    public var oldGroupModel: TSGroupModel? {
        return infoMessageValue(forKey: .oldGroupModel)
    }

    @objc
    public var newGroupModel: TSGroupModel? {
        return infoMessageValue(forKey: .newGroupModel)
    }

    public var oldDisappearingMessageToken: DisappearingMessageToken? {
        return infoMessageValue(forKey: .oldDisappearingMessageToken)
    }

    public var newDisappearingMessageToken: DisappearingMessageToken? {
        return infoMessageValue(forKey: .newDisappearingMessageToken)
    }

    fileprivate var groupUpdateSourceAddress: SignalServiceAddress? {
        return infoMessageValue(forKey: .groupUpdateSourceAddress)
    }

    fileprivate var profileChanges: ProfileChanges? {
        return infoMessageValue(forKey: .profileChanges)
    }
}
