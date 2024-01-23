//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// MARK: - Group updates

public extension TSInfoMessage {

    static func newGroupUpdateInfoMessage(
        timestamp: UInt64,
        groupThread: TSGroupThread,
        updateItems: [PersistableGroupUpdateItem]
    ) -> TSInfoMessage {
        owsAssert(!updateItems.isEmpty)

        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]

        userInfoForNewMessage[.groupUpdateItems] = PersistableGroupUpdateItemsWrapper(updateItems)

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            timestamp: timestamp,
            messageType: .typeGroupUpdate,
            infoMessageUserInfo: userInfoForNewMessage
        )
        return infoMessage
    }

    @objc
    func groupUpdateDescription(transaction tx: SDSAnyReadTransaction) -> NSAttributedString {
        let fallback = DisplayableGroupUpdateItem.genericUpdateByUnknownUser.localizedText

        guard let localIdentifiers: LocalIdentifiers =
                DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            return fallback
        }

        let updateItems: [DisplayableGroupUpdateItem]

        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {

        case .nonGroupUpdate:
            return fallback

        case .legacyRawString(let string):
            return NSAttributedString(string: string)

        case .newGroup, .modelDiff, .precomputed:
            guard let items = buildGroupUpdateItems(
                localIdentifiers: localIdentifiers,
                tx: tx.asV2Read,
                transformer: { builder, precomputedItems, tx in
                    return builder.displayableUpdateItemsForPrecomputed(
                        precomputedUpdateItems: precomputedItems,
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                }
            ) else {
                return fallback
            }

            updateItems = items
        }

        guard let firstUpdateItem = updateItems.first else {
            owsFailBeta("Should never have an empty update items list!")
            return NSAttributedString()
        }

        let initialString = NSMutableAttributedString(
            attributedString: firstUpdateItem.localizedText
        )

        return updateItems.dropFirst().reduce(initialString) { partialResult, updateItem in
            partialResult.append("\n")
            partialResult.append(updateItem.localizedText)
            return partialResult
        }
    }

    func computedGroupUpdateItems(
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyReadTransaction
    ) -> [PersistableGroupUpdateItem]? {
        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .legacyRawString, .nonGroupUpdate:
            return nil

        case .newGroup, .modelDiff, .precomputed:
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
                tx: tx.asV2Read
            ) else {
                owsFailDebug("Missing local identifiers!")
                return nil
            }

            return buildGroupUpdateItems(
                localIdentifiers: localIdentifiers,
                tx: tx.asV2Read,
                transformer: { _, items, _ in return items }
            )
        }
    }

    func displayableGroupUpdateItems(
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyReadTransaction
    ) -> [DisplayableGroupUpdateItem]? {
        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .legacyRawString, .nonGroupUpdate:
            return nil

        case .newGroup, .modelDiff, .precomputed:
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
                tx: tx.asV2Read
            ) else {
                owsFailDebug("Missing local identifiers!")
                return nil
            }

            return buildGroupUpdateItems(
                localIdentifiers: localIdentifiers,
                tx: tx.asV2Read,
                transformer: { builder, precomputedItems, tx in
                    return builder.displayableUpdateItemsForPrecomputed(
                        precomputedUpdateItems: precomputedItems,
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                }
            )
        }
    }

    private func buildGroupUpdateItems<T>(
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
        transformer: (
            _ builder: GroupUpdateItemBuilder,
            _ precomputedItems: [PersistableGroupUpdateItem],
            _ tx: DBReadTransaction
        ) -> [T]
    ) -> [T]? {
        lazy var groupUpdateItemBuilder = GroupUpdateItemBuilderImpl(
            contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(
                contactsManager
            ),
            signalRecipientStore: DependenciesBridge.shared.signalRecipientStore
        )

        let precomputedItems: [PersistableGroupUpdateItem]

        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {

        case .nonGroupUpdate, .legacyRawString:
            return nil

        case .precomputed(let precomputedUpdateItems):
            precomputedItems = precomputedUpdateItems.updateItems

        case let .newGroup(newGroupModel, updateMetadata):
            precomputedItems = groupUpdateItemBuilder.precomputedUpdateItemsForNewGroup(
                newGroupModel: newGroupModel.groupModel,
                newDisappearingMessageToken: newGroupModel.dmToken,
                localIdentifiers: localIdentifiers,
                groupUpdateSource: updateMetadata.source,
                tx: tx
            )

        case let .modelDiff(oldGroupModel, newGroupModel, updateMetadata):
            precomputedItems = groupUpdateItemBuilder.precomputedUpdateItemsByDiffingModels(
                oldGroupModel: oldGroupModel.groupModel,
                newGroupModel: newGroupModel.groupModel,
                oldDisappearingMessageToken: oldGroupModel.dmToken,
                newDisappearingMessageToken: newGroupModel.dmToken,
                localIdentifiers: localIdentifiers,
                groupUpdateSource: updateMetadata.source,
                tx: tx
            )
        }

        return transformer(
            groupUpdateItemBuilder,
            precomputedItems,
            tx
        )
    }
}

// MARK: -

public extension TSInfoMessage {
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

    @objc
    func sessionSwitchoverDescription(tx: SDSAnyReadTransaction) -> String {
        if let phoneNumber = infoMessageUserInfo?[.sessionSwitchoverPhoneNumber] as? String {
            let displayName = contactThreadDisplayName(tx: tx)
            let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber)
            let formatString = OWSLocalizedString(
                "SESSION_SWITCHOVER_EVENT",
                comment: "If you send a message to a phone number, we might not know the owner of the account. When you later learn the owner of the account, we may show this message. The first parameter is a phone number; the second parameter is the contact's name. Put differently, this message indicates that a phone number belongs to a particular named recipient."
            )
            return String(format: formatString, formattedPhoneNumber, displayName)
        } else {
            let address = TSContactThread.contactAddress(fromThreadId: uniqueThreadId, transaction: tx)
            return TSErrorMessage.safetyNumberChangeDescription(for: address, tx: tx)
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

    @objc
    static func legacyDisappearingMessageUpdateDescription(
        token newToken: DisappearingMessageToken,
        wasAddedToExistingGroup: Bool,
        updaterName: String?
    ) -> String {
        // This might be zero if DMs are not enabled.
        let durationString = String.formatDurationLossless(
            durationSeconds: newToken.durationSeconds
        )

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

    public enum GroupUpdateMetadata {
        public struct UpdateMetadata {
            public let source: GroupUpdateSource
            /// Whether we determined, at the time we created this info message, that
            /// the updater was the local user.
            /// - Returns
            /// `true` if we knew conclusively that the updater was the local user, and
            /// `false` otherwise.
            public let updaterWasLocalUser: Bool
        }

        public struct GroupModel {
            public let groupModel: TSGroupModel
            public let dmToken: DisappearingMessageToken?
        }

        /// For legacy group updates we persisted a pre-rendered string, rather than the details
        /// to generate that string.
        case legacyRawString(String)

        // For some time after we would persist the group state before and after
        // (or just the new group state) along with other optional metadata.
        // This will be soon unused at write time, but can still be present
        // in the database as there was no migration done.
        case newGroup(GroupModel, updateMetadata: UpdateMetadata)
        case modelDiff(old: GroupModel, new: GroupModel, updateMetadata: UpdateMetadata)

        /// Modern group updates are precomputed into an enum and stored with all necessary metadata
        /// strongly typed, whether its a new group or an update to an existing group.
        /// Group state is NOT stored with these types.
        case precomputed(PersistableGroupUpdateItemsWrapper)

        /// This is not a group update.
        case nonGroupUpdate
    }

    public func groupUpdateMetadata(localIdentifiers: LocalIdentifiers) -> GroupUpdateMetadata {
        if let precomputed: PersistableGroupUpdateItemsWrapper =
            infoMessageValue(forKey: .groupUpdateItems)
        {
            return .precomputed(precomputed)
        } else if let legacyPrecomputed: LegacyPersistableGroupUpdateItemsWrapper =
            infoMessageValue(forKey: .legacyGroupUpdateItems)
        {
            let updateMetadata = self.persistedLegacyUpdateMetadata
            // Convert the legacy items into new items.
            let mappedItems: [PersistableGroupUpdateItem] = legacyPrecomputed
                .updateItems
                .compactMap { legacyItem in
                    return legacyItem.toNewItem(
                        updater: updateMetadata.source,
                        oldGroupModel: infoMessageValue(forKey: .oldGroupModel),
                        localIdentifiers: localIdentifiers
                    )
                }
            return .precomputed(.init(mappedItems))
        } else if
            let newGroupModel: TSGroupModel = infoMessageValue(forKey: .newGroupModel)
        {
            let updateMetadata = self.persistedLegacyUpdateMetadata

            if let oldGroupModel: TSGroupModel = infoMessageValue(forKey: .oldGroupModel) {
                return .modelDiff(
                    old: .init(
                        groupModel: oldGroupModel,
                        dmToken: infoMessageValue(forKey: .oldDisappearingMessageToken)
                    ),
                    new: .init(
                        groupModel: newGroupModel,
                        dmToken: infoMessageValue(forKey: .newDisappearingMessageToken)
                    ),
                    updateMetadata: updateMetadata
                )
            } else {
                return .newGroup(
                    .init(
                        groupModel: newGroupModel,
                        dmToken: infoMessageValue(forKey: .newDisappearingMessageToken)
                    ),
                    updateMetadata: updateMetadata
                )
            }
        } else if let customMessage {
            return .legacyRawString(customMessage)
        } else {
            if messageType == .typeGroupUpdate {
                owsFailDebug("Group update should contain some metadata!")
            }
            return .nonGroupUpdate
        }
    }

    /// We only stored this legacy data before we persisted the new ``TSInfoMessage.PersistableGroupUpdateItem``,
    /// so it lives either alongside a model diff or alongside ``TSInfoMessage.LegacyPersistableGroupUpdateItem``.
    private var persistedLegacyUpdateMetadata: GroupUpdateMetadata.UpdateMetadata {
        let source = Self.legacyGroupUpdateSource(infoMessageUserInfoDict: infoMessageUserInfo)
        // We grab this legacy value if we have it; its irrelevant for new persistable
        // update items which know if they are from the local user or not.
        let updaterWasLocalUser: Bool =
            infoMessageValue(forKey: .legacyUpdaterKnownToBeLocalUser) ?? false

        return GroupUpdateMetadata.UpdateMetadata(
            source: source,
            updaterWasLocalUser: updaterWasLocalUser
        )
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

    public func setGroupUpdateItemsWrapper(_ updateItemsWrapper: PersistableGroupUpdateItemsWrapper) {
        setInfoMessageValue(updateItemsWrapper, forKey: .groupUpdateItems)
    }
}
