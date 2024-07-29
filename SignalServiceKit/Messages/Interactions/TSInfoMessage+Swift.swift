//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// MARK: - Group updates

public enum GroupUpdateSpamReportingMetadata {
    // This update contains information that can be reported as spam.
    case reportable(serverGuid: String)
    // This update is missing necessary information to report as spam.
    // This could be because the information was dropped (as with the round trip to a backup)
    // or the serverGuid is otherwise missing. This information being missing
    // isn't a fatal error, it just means that no attempt will be made to record or report
    // spam based on this group action.
    case unreportable
    // We can't report this update because it came from a group action (create, join, etc.)
    // intiated locally by the user.
    case createdByLocalAction
    // These updates were initiated locally to update the group state.
    // there's no metadata to associate with these updates for reporting purposes.
    case learnedByLocallyInitatedRefresh
}

public extension TSInfoMessage {

    static func newGroupUpdateInfoMessage(
        timestamp: UInt64,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        updateItems: [PersistableGroupUpdateItem]
    ) -> TSInfoMessage {
        owsPrecondition(!updateItems.isEmpty)

        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]

        userInfoForNewMessage[.groupUpdateItems] = PersistableGroupUpdateItemsWrapper(updateItems)

        let spamReportingServerGuid: String? = {
            switch spamReportingMetadata {
            case .reportable(serverGuid: let serverGuid):
                return serverGuid
            case .unreportable, .createdByLocalAction, .learnedByLocallyInitatedRefresh:
                return nil
            }
        }()

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            timestamp: timestamp,
            serverGuid: spamReportingServerGuid,
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
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
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
    struct PhoneNumberChangeInfo {
        public let aci: Aci
        /// This may be missing, for example on info messages from a backup.
        public let oldNumber: String?
        /// This may be missing, for example on info messages from a backup.
        public let newNumber: String?

        fileprivate init(aci: Aci, oldNumber: String?, newNumber: String?) {
            self.aci = aci
            self.oldNumber = oldNumber
            self.newNumber = newNumber
        }
    }

    func phoneNumberChangeInfo() -> PhoneNumberChangeInfo? {
        guard
            let infoMessageUserInfo,
            let aciString = infoMessageUserInfo[.changePhoneNumberAciString] as? String,
            let aci = Aci.parseFrom(aciString: aciString)
        else { return nil }

        return PhoneNumberChangeInfo(
            aci: aci,
            oldNumber: infoMessageUserInfo[.changePhoneNumberOld] as? String,
            newNumber: infoMessageUserInfo[.changePhoneNumberNew] as? String
        )
    }

    @objc
    func phoneNumberChangeInfoAci() -> AciObjC? {
        guard let aci = phoneNumberChangeInfo()?.aci else { return nil }
        return AciObjC(aci)
    }

    func setPhoneNumberChangeInfo(
        aci: Aci,
        oldNumber: String?,
        newNumber: E164?
    ) {
        setInfoMessageValue(aci.serviceIdUppercaseString, forKey: .changePhoneNumberAciString)

        if let oldNumber {
            setInfoMessageValue(oldNumber, forKey: .changePhoneNumberOld)
        }
        if let newNumber {
            setInfoMessageValue(newNumber.stringValue, forKey: .changePhoneNumberNew)
        }
    }
}

// MARK: -

extension TSInfoMessage {
    static func makeForThreadMerge(
        mergedThread: TSContactThread,
        previousE164: String?
    ) -> TSInfoMessage {
        let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = if let previousE164 {
            [.threadMergePhoneNumber: previousE164]
        } else {
            [:]
        }

        return TSInfoMessage(
            thread: mergedThread,
            messageType: .threadMerge,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

public extension TSInfoMessage {
    /// If this info message represents an E164/PNI -> ACI thread merge event,
    /// returns the "before" thread's E164.
    var threadMergePhoneNumber: String? {
        return infoMessageValue(forKey: .threadMergePhoneNumber)
    }

    @objc
    func threadMergeDescription(tx: SDSAnyReadTransaction) -> String {
        let displayName = contactThreadDisplayName(tx: tx)
        if let phoneNumber = threadMergePhoneNumber {
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
}

// MARK: -

extension TSInfoMessage {
    static func makeForSessionSwitchover(
        contactThread: TSContactThread,
        phoneNumber: String?
    ) -> TSInfoMessage {
        let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = if let phoneNumber {
            [.sessionSwitchoverPhoneNumber: phoneNumber]
        } else {
            [:]
        }

        return TSInfoMessage(
            thread: contactThread,
            messageType: .sessionSwitchover,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

public extension TSInfoMessage {
    var sessionSwitchoverPhoneNumber: String? {
        return infoMessageValue(forKey: .sessionSwitchoverPhoneNumber)
    }

    @objc
    func sessionSwitchoverDescription(tx: SDSAnyReadTransaction) -> String {
        if let phoneNumber = sessionSwitchoverPhoneNumber {
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
}

// MARK: -

extension TSInfoMessage {
    /// The display names we'll use before learning someone's profile key.
    public enum DisplayNameBeforeLearningProfileName {
        case phoneNumber(String)
        case username(String)
    }

    static func insertLearnedProfileNameMessage(
        serviceId: ServiceId,
        displayNameBefore: DisplayNameBeforeLearningProfileName,
        tx: any DBWriteTransaction
    ) {
        let threadStore = DependenciesBridge.shared.threadStore
        let interactionStore = DependenciesBridge.shared.interactionStore

        guard let contactThread = threadStore.fetchContactThreads(
            serviceId: serviceId,
            tx: tx
        ).first else { return }

        let infoMessage: TSInfoMessage = .makeForLearnedProfileName(
            contactThread: contactThread,
            displayNameBefore: displayNameBefore
        )
        interactionStore.insertInteraction(infoMessage, tx: tx)
    }

    private static func makeForLearnedProfileName(
        contactThread: TSContactThread,
        displayNameBefore: DisplayNameBeforeLearningProfileName
    ) -> TSInfoMessage {
        let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = switch displayNameBefore {
        case .phoneNumber(let phoneNumber):
            [.phoneNumberDisplayNameBeforeLearningProfileName: phoneNumber]
        case .username(let username):
            [.usernameDisplayNameBeforeLearningProfileName: username]
        }

        return TSInfoMessage(
            thread: contactThread,
            messageType: .learnedProfileName,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

public extension TSInfoMessage {
    var displayNameBeforeLearningProfileName: DisplayNameBeforeLearningProfileName? {
        if let phoneNumber: String = infoMessageValue(forKey: .phoneNumberDisplayNameBeforeLearningProfileName) {
            return .phoneNumber(phoneNumber)
        } else if let username: String = infoMessageValue(forKey: .usernameDisplayNameBeforeLearningProfileName) {
            return .username(username)
        }

        return nil
    }

    @objc
    func learnedProfileNameDescription(tx: SDSAnyReadTransaction) -> String {
        guard let displayNameBeforeLearningProfileName else {
            return ""
        }

        let format = OWSLocalizedString(
            "INFO_MESSAGE_LEARNED_PROFILE_KEY",
            comment: "When you start a chat with someone and then later learn their profile name, we insert an in-chat message with this string to record the identifier you originally used to contact them. Embeds {{ the identifier, either a phone number or a username }}."
        )

        switch displayNameBeforeLearningProfileName {
        case .phoneNumber(let phoneNumber):
            return String(format: format, phoneNumber)
        case .username(let username):
            return String(format: format, username)
        }
    }
}

// MARK: -

public extension TSInfoMessage {
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
    static func paymentsActivatedMessage(
        thread: TSThread,
        senderAci: Aci
    ) -> TSInfoMessage {
        return TSInfoMessage(
            thread: thread,
            messageType: .paymentsActivated,
            infoMessageUserInfo: [
                .paymentActivatedAci: senderAci.serviceIdString
            ]
        )
    }

    static func paymentsActivationRequestMessage(
        thread: TSThread,
        senderAci: Aci
    ) -> TSInfoMessage {
        return TSInfoMessage(
            thread: thread,
            messageType: .paymentsActivationRequest,
            infoMessageUserInfo: [
                .paymentActivationRequestSenderAci: senderAci.serviceIdString
            ]
        )
    }
}

extension TSInfoMessage {
    public enum PaymentsInfoMessageAuthor: Hashable, Equatable {
        case localUser
        case otherUser(Aci)
    }

    public func paymentsActivationRequestAuthor(localIdentifiers: LocalIdentifiers) -> PaymentsInfoMessageAuthor? {
        guard
            let requestSenderAciString: String = infoMessageValue(forKey: .paymentActivationRequestSenderAci),
            let requestSenderAci = Aci.parseFrom(aciString: requestSenderAciString)
        else { return nil }

        return paymentsInfoMessageAuthor(
            identifyingAci: requestSenderAci,
            localIdentifiers: localIdentifiers
        )
    }

    public func paymentsActivatedAuthor(localIdentifiers: LocalIdentifiers) -> PaymentsInfoMessageAuthor? {
        guard
            let authorAciString: String = infoMessageValue(forKey: .paymentActivatedAci),
            let authorAci = Aci.parseFrom(aciString: authorAciString)
        else { return nil }

        return paymentsInfoMessageAuthor(
            identifyingAci: authorAci,
            localIdentifiers: localIdentifiers
        )
    }

    private func paymentsInfoMessageAuthor(
        identifyingAci: Aci?,
        localIdentifiers: LocalIdentifiers
    ) -> PaymentsInfoMessageAuthor? {
        guard let identifyingAci else { return nil }

        if identifyingAci == localIdentifiers.aci {
            return .localUser
        } else {
            return .otherUser(identifyingAci)
        }
    }

    // MARK: -

    private enum PaymentsInfoMessageType {
        case incoming(from: Aci)
        case outgoing(to: Aci)
    }

    private func paymentsActivationRequestType(transaction tx: SDSAnyReadTransaction) -> PaymentsInfoMessageType? {
        return paymentsInfoMessageType(
            authorBlock: self.paymentsActivationRequestAuthor(localIdentifiers:),
            tx: tx.asV2Read
        )
    }

    private func paymentsActivatedType(transaction tx: SDSAnyReadTransaction) -> PaymentsInfoMessageType? {
        return paymentsInfoMessageType(
            authorBlock: self.paymentsActivatedAuthor(localIdentifiers:),
            tx: tx.asV2Read
        )
    }

    private func paymentsInfoMessageType(
        authorBlock: (LocalIdentifiers) -> PaymentsInfoMessageAuthor?,
        tx: any DBReadTransaction
    ) -> PaymentsInfoMessageType? {
        guard let localIdentiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
            return nil
        }

        switch authorBlock(localIdentiers) {
        case nil:
            return nil
        case .localUser:
            guard
                let contactThread = DependenciesBridge.shared.threadStore
                    .fetchThreadForInteraction(self, tx: tx) as? TSContactThread,
                let contactAci = contactThread.contactAddress.aci
            else { return nil }

            return .outgoing(to: contactAci)
        case .otherUser(let authorAci):
            return .incoming(from: authorAci)
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

        let displayName = contactsManager.displayName(for: SignalServiceAddress(aci), tx: transaction)
        return String(format: formatString, displayName.resolvedValue())
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
            let displayName = contactsManager.displayName(for: SignalServiceAddress(aci), tx: transaction)
            let format = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_FINISHED",
                comment: "Shown when a user activates payments from a chat. Embeds: {{ the user's name}}"
            )
            return String(format: format, displayName.resolvedValue())
        }
    }
}

// MARK: - Group Updates

extension TSInfoMessage {
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
        if let precomputed = infoMessageUserInfo?[.groupUpdateItems] as? PersistableGroupUpdateItemsWrapper {
            return .precomputed(precomputed)
        } else if let legacyPrecomputed = infoMessageUserInfo?[.legacyGroupUpdateItems] as? LegacyPersistableGroupUpdateItemsWrapper {
            let updateMetadata = self.persistedLegacyUpdateMetadata
            // Convert the legacy items into new items.
            let mappedItems: [PersistableGroupUpdateItem] = legacyPrecomputed
                .updateItems
                .compactMap { legacyItem in
                    return legacyItem.toNewItem(
                        updater: updateMetadata.source,
                        oldGroupModel: infoMessageUserInfo?[.oldGroupModel] as? TSGroupModel,
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

    public func setGroupUpdateItemsWrapper(_ updateItemsWrapper: PersistableGroupUpdateItemsWrapper) {
        setInfoMessageValue(updateItemsWrapper, forKey: .groupUpdateItems)
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
}

// MARK: -

private extension TSInfoMessage {
    func contactThreadDisplayName(tx: SDSAnyReadTransaction) -> String {
        let result: String? = {
            guard let address = TSContactThread.contactAddress(fromThreadId: uniqueThreadId, transaction: tx) else {
                return nil
            }
            return contactsManager.displayName(for: address, tx: tx).resolvedValue()
        }()
        return result ?? CommonStrings.unknownUser
    }
}

// MARK: - InfoMessageUserInfo

extension TSInfoMessage {
    private func infoMessageValue<T>(forKey key: InfoMessageUserInfoKey) -> T? {
        guard let value = infoMessageUserInfo?[key] as? T else {
            return nil
        }

        return value
    }

    private func setInfoMessageValue(_ value: Any, forKey key: InfoMessageUserInfoKey) {
        if self.infoMessageUserInfo != nil {
            self.infoMessageUserInfo![key] = value
        } else {
            self.infoMessageUserInfo = [key: value]
        }
    }
}
