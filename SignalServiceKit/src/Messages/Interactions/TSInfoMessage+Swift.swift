//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension TSInfoMessage {

    @objc
    func groupUpdateDescription(transaction: SDSAnyReadTransaction) -> NSAttributedString {
        // for legacy group updates we persisted a pre-rendered string, rather than the details
        // to generate that string
        if let customMessage = self.customMessage {
            return NSAttributedString(string: customMessage)
        }

        guard
            let newGroupModel,
            let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)
        else {
            return GroupUpdateItemBuilderImpl(
                contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactsManager)
            ).defaultGroupUpdateItem(
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                localIdentifiers: nil,
                tx: transaction.asV2Read
            ).localizedText
        }

        return groupUpdateDescription(
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )
    }

    func groupUpdateItems(transaction: SDSAnyReadTransaction) -> [GroupUpdateItem]? {
        guard
            customMessage == nil,
            let newGroupModel
        else {
            // Legacy group updates persisted a pre-rendered string.
            return nil
        }

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
            tx: transaction.asV2Read
        ) else {
            owsFailDebug("Missing local identifiers!")
            return nil
        }

        return buildGroupUpdateItems(
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )
    }

    @objc
    func profileChangeDescription(transaction: SDSAnyReadTransaction) -> String {
        guard let profileChanges = profileChanges,
            let updateDescription = profileChanges.descriptionForUpdate(transaction: transaction) else {
                owsFailDebug("Unexpectedly missing update description for profile change")
            return ""
        }

        return updateDescription
    }

    @objc
    func threadMergeDescription(tx: SDSAnyReadTransaction) -> String {
        let displayName = contactThreadDisplayName(tx: tx)
        if let phoneNumber = infoMessageUserInfo?[.threadMergePhoneNumber] as? String {
            let formatString = OWSLocalizedString(
                "THREAD_MERGE_PHONE_NUMBER",
                comment: "A system event shown in a conversation when multiple conversations for the same person have been merged into one. The parameters are replaced with the contact's name (eg John Doe) and their phone number (eg +1 650 555 0100)."
            )
            let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber)
            return String(format: formatString, displayName, formattedPhoneNumber)
        } else {
            let formatString = OWSLocalizedString(
                "THREAD_MERGE_NO_PHONE_NUMBER",
                comment: "A system event shown in a conversation when multiple conversations for the same person have been merged into one. The parameter is replaced with the contact's name (eg John Doe)."
            )
            return String(format: formatString, displayName)
        }
    }

    private func contactThreadDisplayName(tx: SDSAnyReadTransaction) -> String {
        let result: String? = {
            guard let address = TSContactThread.contactAddress(fromThreadId: uniqueThreadId, transaction: tx) else {
                return nil
            }
            return contactsManager.displayName(for: address, transaction: tx)
        }()
        return result ?? OWSLocalizedString("UNKNOWN_USER", comment: "Label indicating an unknown user.")
    }

    var profileChangeAddress: SignalServiceAddress? {
        return profileChanges?.address
    }

    var profileChangesOldFullName: String? {
        profileChanges?.oldFullName
    }

    var profileChangeNewNameComponents: PersonNameComponents? {
        return profileChanges?.newNameComponents
    }
}

// MARK: -

extension TSInfoMessage {
    private func groupUpdateDescription(
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyReadTransaction
    ) -> NSAttributedString {
        let updateItems = buildGroupUpdateItems(
            newGroupModel: newGroupModel,
            localIdentifiers: localIdentifiers,
            transaction: transaction
        )

        guard let firstUpdateItem = updateItems.first else {
            owsFailBeta("Should never have an empty update items list!")
            return NSAttributedString()
        }

        let initialString = NSMutableAttributedString(attributedString: firstUpdateItem.localizedText)

        return updateItems.dropFirst().reduce(initialString) { partialResult, updateItem in
            partialResult.append("\n")
            partialResult.append(updateItem.localizedText)
            return partialResult
        }
    }

    private func buildGroupUpdateItems(
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyReadTransaction
    ) -> [GroupUpdateItem] {
        return GroupUpdateItemBuilderImpl(
            contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactsManager)
        ).buildUpdateItems(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterWasLocalUser,
            updateMessages: updateMessages,
            tx: transaction.asV2Read
        )
    }

    @objc
    public static func legacyDisappearingMessageUpdateDescription(token newToken: DisappearingMessageToken,
                                                                  wasAddedToExistingGroup: Bool,
                                                                  updaterName: String?) -> String {

        // This might be zero if DMs are not enabled.
        let durationString = newToken.durationString

        if wasAddedToExistingGroup {
            assert(newToken.isEnabled)
            let format = OWSLocalizedString("DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
                                           comment: "Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
            return String(format: format, durationString)
        } else if let updaterName = updaterName {
            if newToken.isEnabled {
                let format = OWSLocalizedString("OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                return String(format: format, updaterName, durationString)
            } else {
                let format = OWSLocalizedString("OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}.")
                return String(format: format, updaterName)
            }
        } else {
            // Changed by localNumber on this device or via synced transcript
            if newToken.isEnabled {
                let format = OWSLocalizedString("YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when you update disappearing messages duration. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                return String(format: format, durationString)
            } else {
                return OWSLocalizedString("YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                         comment: "Info Message when you disabled disappearing messages.")
            }
        }
    }
}

// MARK: Payments

extension TSInfoMessage {

    private enum PaymentsInfoMessageType {
        case incoming(from: Aci)
        case outgoing(to: Aci)
    }

    private func paymentsActivationRequestType(transaction: SDSAnyReadTransaction) -> PaymentsInfoMessageType? {
        guard
            let paymentActivationRequestSenderAci,
            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aci
        else {
            return nil
        }
        if paymentActivationRequestSenderAci == localAci {
            guard let peerAci = TSContactThread.contactAddress(
                fromThreadId: self.uniqueThreadId,
                transaction: transaction
            )?.aci else {
                return nil
            }
            return .outgoing(to: peerAci)
        } else {
            return .incoming(from: paymentActivationRequestSenderAci)
        }
    }

    private func paymentsActivatedType(transaction: SDSAnyReadTransaction) -> PaymentsInfoMessageType? {
        guard
            let paymentActivatedAci,
            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aci
        else {
            return nil
        }
        if paymentActivatedAci == localAci {
            guard let peerAci = TSContactThread.contactAddress(
                fromThreadId: self.uniqueThreadId,
                transaction: transaction
            )?.aci else {
                return nil
            }
            return .outgoing(to: peerAci)
        } else {
            return .incoming(from: paymentActivatedAci)
        }
    }

    public func isIncomingPaymentsActivationRequest(_ tx: SDSAnyReadTransaction) -> Bool {
        switch paymentsActivationRequestType(transaction: tx) {
        case .none, .outgoing:
            return false
        case .incoming:
            return true
        }
    }

    public func isIncomingPaymentsActivated(_ tx: SDSAnyReadTransaction) -> Bool {
        switch paymentsActivatedType(transaction: tx) {
        case .none, .outgoing:
            return false
        case .incoming:
            return true
        }
    }

    @objc
    func paymentsActivationRequestDescription(transaction: SDSAnyReadTransaction) -> String? {
        let aci: Aci
        let formatString: String
        switch paymentsActivationRequestType(transaction: transaction) {
        case .none:
            return nil
        case .incoming(let fromAci):
            aci = fromAci
            formatString = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_RECEIVED",
                comment: "Shown when a user receives a payment activation request. Embeds: {{ the user's name}}"
            )
        case .outgoing(let toAci):
            aci = toAci
            formatString = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_SENT",
                comment: "Shown when requesting a user activates payments. Embeds: {{ the user's name}}"
            )
        }

        let name = contactsManager.displayName(
            for: SignalServiceAddress(aci),
            transaction: transaction
        )
        return String(format: formatString, name)
    }

    @objc
    func paymentsActivatedDescription(transaction: SDSAnyReadTransaction) -> String? {
        switch paymentsActivatedType(transaction: transaction) {
        case .none:
            return nil
        case .outgoing:
            return OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATED",
                comment: "Shown when a user activates payments from a chat"
            )
        case .incoming(let aci):
            let name = contactsManager.displayName(
                for: SignalServiceAddress(aci),
                transaction: transaction
            )
            let format = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_FINISHED",
                comment: "Shown when a user activates payments from a chat. Embeds: {{ the user's name}}"
            )
            return String(format: format, name)
        }
    }
}

// MARK: - InfoMessageUserInfo

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

    public var updateMessages: UpdateMessagesWrapper? {
        return infoMessageValue(forKey: .updateMessages)
    }

    public var oldGroupModel: TSGroupModel? {
        return infoMessageValue(forKey: .oldGroupModel)
    }

    public var newGroupModel: TSGroupModel? {
        return infoMessageValue(forKey: .newGroupModel)
    }

    public var oldDisappearingMessageToken: DisappearingMessageToken? {
        return infoMessageValue(forKey: .oldDisappearingMessageToken)
    }

    public var newDisappearingMessageToken: DisappearingMessageToken? {
        return infoMessageValue(forKey: .newDisappearingMessageToken)
    }

    /// The address of the user to whom this update should be attributed, if
    /// known.
    public var groupUpdateSourceAddress: SignalServiceAddress? {
        return infoMessageValue(forKey: .groupUpdateSourceAddress)
    }

    /// Whether we determined, at the time we created this info message, that
    /// the updater was the local user.
    /// - Returns
    /// `true` if we knew conclusively that the updater was the local user, and
    /// `false` otherwise.
    public var updaterWasLocalUser: Bool {
        return infoMessageValue(forKey: .updaterKnownToBeLocalUser) ?? false
    }

    fileprivate var profileChanges: ProfileChanges? {
        return infoMessageValue(forKey: .profileChanges)
    }

    fileprivate var paymentActivationRequestSenderAci: Aci? {
        guard let raw: String = infoMessageValue(forKey: .paymentActivationRequestSenderAci) else {
            return nil
        }
        return try? Aci.parseFrom(serviceIdString: raw)
    }

    fileprivate var paymentActivatedAci: Aci? {
        guard let raw: String = infoMessageValue(forKey: .paymentActivatedAci) else {
            return nil
        }
        return try? Aci.parseFrom(serviceIdString: raw)
    }
}

extension TSInfoMessage {
    private func setInfoMessageValue(_ value: Any, forKey key: InfoMessageUserInfoKey) {
        if self.infoMessageUserInfo != nil {
            self.infoMessageUserInfo![key] = value
        } else {
            self.infoMessageUserInfo = [key: value]
        }
    }

    public func setUpdateMessages(_ updateMessages: UpdateMessagesWrapper) {
        setInfoMessageValue(updateMessages, forKey: .updateMessages)
    }

    public func setNewGroupModel(_ newGroupModel: TSGroupModel) {
        setInfoMessageValue(newGroupModel, forKey: .newGroupModel)
    }

    public func setNewDisappearingMessageToken(_ newDisappearingMessageToken: DisappearingMessageToken) {
        setInfoMessageValue(newDisappearingMessageToken, forKey: .newDisappearingMessageToken)
    }
}
