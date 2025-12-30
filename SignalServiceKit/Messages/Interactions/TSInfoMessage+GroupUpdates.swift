//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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

extension TSInfoMessage {
    static func makeForGroupUpdate(
        timestamp: UInt64,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        updateItems: [PersistableGroupUpdateItem],
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
            expireTimerVersion: nil,
            expiresInSeconds: 0,
            infoMessageUserInfo: userInfoForNewMessage,
        )
        return infoMessage
    }

    func setGroupUpdateItemsWrapper(_ updateItemsWrapper: PersistableGroupUpdateItemsWrapper) {
        setInfoMessageValue(updateItemsWrapper, forKey: .groupUpdateItems)
    }
}

// MARK: -

public extension TSInfoMessage {
    enum GroupUpdateMetadata {
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
        case newGroup(GroupModel, source: GroupUpdateSource)
        case modelDiff(old: GroupModel, new: GroupModel, source: GroupUpdateSource)

        /// Modern group updates are precomputed into an enum and stored with all necessary metadata
        /// strongly typed, whether its a new group or an update to an existing group.
        /// Group state is NOT stored with these types.
        case precomputed(PersistableGroupUpdateItemsWrapper)

        /// This is not a group update.
        case nonGroupUpdate
    }

    private static var groupUpdateItemBuilder: GroupUpdateItemBuilder {
        return GroupUpdateItemBuilderImpl(
            contactsManager: SSKEnvironment.shared.contactManagerRef,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable,
        )
    }

    // MARK: -

    @objc
    func groupUpdateDescription(transaction tx: DBReadTransaction) -> NSAttributedString {
        let fallback = DisplayableGroupUpdateItem.genericUpdateByUnknownUser.localizedText

        guard
            let localIdentifiers: LocalIdentifiers = DependenciesBridge.shared.tsAccountManager
                .localIdentifiers(tx: tx)
        else {
            return fallback
        }

        let updateItems: [DisplayableGroupUpdateItem]

        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {

        case .nonGroupUpdate:
            return fallback

        case .legacyRawString(let string):
            return NSAttributedString(string: string)

        case .newGroup, .modelDiff, .precomputed:
            guard
                let persistableItems = computedGroupUpdateItems(
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )
            else {
                return fallback
            }

            updateItems = Self.groupUpdateItemBuilder.displayableUpdateItemsForPrecomputed(
                precomputedUpdateItems: persistableItems,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        }

        guard let firstUpdateItem = updateItems.first else {
            owsFailBeta("Should never have an empty update items list!")
            return NSAttributedString()
        }

        let initialString = NSMutableAttributedString(
            attributedString: firstUpdateItem.localizedText,
        )

        return updateItems.dropFirst().reduce(initialString) { partialResult, updateItem in
            partialResult.append("\n")
            partialResult.append(updateItem.localizedText)
            return partialResult
        }
    }

    func displayableGroupUpdateItems(
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> [DisplayableGroupUpdateItem]? {
        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .legacyRawString, .nonGroupUpdate:
            return nil

        case .newGroup, .modelDiff, .precomputed:
            guard
                let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
                    tx: tx,
                )
            else {
                owsFailDebug("Missing local identifiers!")
                return nil
            }

            return computedGroupUpdateItems(
                localIdentifiers: localIdentifiers,
                tx: tx,
            ).map {
                Self.groupUpdateItemBuilder.displayableUpdateItemsForPrecomputed(
                    precomputedUpdateItems: $0,
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )
            }
        }
    }

    // MARK: -

    func computedGroupUpdateItems(
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> [PersistableGroupUpdateItem]? {
        return Self.computedGroupUpdateItems(
            infoMessageUserInfo: infoMessageUserInfo,
            customMessage: customMessage,
            localIdentifiers: localIdentifiers,
            tx: tx,
        )
    }

    static func computedGroupUpdateItems(
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?,
        customMessage: String?,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> [PersistableGroupUpdateItem]? {
        switch groupUpdateMetadata(
            infoMessageUserInfo: infoMessageUserInfo,
            customMessage: customMessage,
            localIdentifiers: localIdentifiers,
        ) {
        case .nonGroupUpdate, .legacyRawString:
            return nil

        case .precomputed(let precomputedUpdateItems):
            return precomputedUpdateItems.updateItems

        case let .newGroup(newGroupModel, source):
            return groupUpdateItemBuilder.precomputedUpdateItemsForNewGroup(
                newGroupModel: newGroupModel.groupModel,
                newDisappearingMessageToken: newGroupModel.dmToken,
                localIdentifiers: localIdentifiers,
                groupUpdateSource: source,
                tx: tx,
            )

        case let .modelDiff(oldGroupModel, newGroupModel, source):
            return groupUpdateItemBuilder.precomputedUpdateItemsByDiffingModels(
                oldGroupModel: oldGroupModel.groupModel,
                newGroupModel: newGroupModel.groupModel,
                oldDisappearingMessageToken: oldGroupModel.dmToken,
                newDisappearingMessageToken: newGroupModel.dmToken,
                localIdentifiers: localIdentifiers,
                groupUpdateSource: source,
                tx: tx,
            )
        }
    }

    // MARK: -

    func groupUpdateMetadata(localIdentifiers: LocalIdentifiers) -> GroupUpdateMetadata {
        return Self.groupUpdateMetadata(
            infoMessageUserInfo: infoMessageUserInfo,
            customMessage: customMessage,
            localIdentifiers: localIdentifiers,
        )
    }

    private static func groupUpdateMetadata(
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?,
        customMessage: String?,
        localIdentifiers: LocalIdentifiers,
    ) -> GroupUpdateMetadata {
        if let precomputed = infoMessageUserInfo?[.groupUpdateItems] as? PersistableGroupUpdateItemsWrapper {
            return .precomputed(precomputed)
        } else if let legacyPrecomputed = infoMessageUserInfo?[.legacyGroupUpdateItems] as? LegacyPersistableGroupUpdateItemsWrapper {
            let source = persistedLegacyUpdateSource(infoMessageUserInfo: infoMessageUserInfo)

            // Convert the legacy items into new items.
            let mappedItems: [PersistableGroupUpdateItem] = legacyPrecomputed
                .updateItems
                .compactMap { legacyItem in
                    return legacyItem.toNewItem(
                        updater: source,
                        oldGroupModel: infoMessageUserInfo?[.oldGroupModel] as? TSGroupModel,
                        localIdentifiers: localIdentifiers,
                    )
                }
            return .precomputed(.init(mappedItems))
        } else if
            let newGroupModel = infoMessageUserInfo?[.newGroupModel] as? TSGroupModel
        {
            let source = persistedLegacyUpdateSource(infoMessageUserInfo: infoMessageUserInfo)

            if let oldGroupModel = infoMessageUserInfo?[.oldGroupModel] as? TSGroupModel {
                return .modelDiff(
                    old: GroupUpdateMetadata.GroupModel(
                        groupModel: oldGroupModel,
                        dmToken: infoMessageUserInfo?[.oldDisappearingMessageToken] as? DisappearingMessageToken,
                    ),
                    new: GroupUpdateMetadata.GroupModel(
                        groupModel: newGroupModel,
                        dmToken: infoMessageUserInfo?[.newDisappearingMessageToken] as? DisappearingMessageToken,
                    ),
                    source: source,
                )
            } else {
                return .newGroup(
                    GroupUpdateMetadata.GroupModel(
                        groupModel: newGroupModel,
                        dmToken: infoMessageUserInfo?[.newDisappearingMessageToken] as? DisappearingMessageToken,
                    ),
                    source: source,
                )
            }
        } else if let customMessage {
            return .legacyRawString(customMessage)
        } else {
            return .nonGroupUpdate
        }
    }

    /// Prior to ``TSInfoMessage/PersistableGroupUpdateItem``, which embeds the
    /// group update source, said source lived alongside a model diff or a
    /// ``TSInfoMessage/LegacyPersistableGroupUpdateItem``.
    private static func persistedLegacyUpdateSource(
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?,
    ) -> GroupUpdateSource {
        guard let infoMessageUserInfoDict = infoMessageUserInfo else {
            return .unknown
        }

        // Legacy cases stored if they were known local users.
        let isKnownLocalUser: () -> Bool = {
            if let storedValue = infoMessageUserInfoDict[.legacyUpdaterKnownToBeLocalUser] as? Bool {
                return storedValue
            }

            // Check for legacy persisted enum state.
            if
                let legacyPrecomputed = infoMessageUserInfoDict[.legacyGroupUpdateItems]
                as? LegacyPersistableGroupUpdateItemsWrapper,
                case let .inviteRemoved(_, wasLocalUser) = legacyPrecomputed.updateItems.first
            {
                return wasLocalUser
            }
            return false
        }

        guard let address = infoMessageUserInfoDict[.groupUpdateSourceLegacyAddress] as? SignalServiceAddress else {
            return .unknown
        }
        if let aci = address.serviceId as? Aci {
            if isKnownLocalUser() {
                return .localUser(originalSource: .aci(aci))
            }
            return .aci(aci)
        } else if let pni = address.serviceId as? Pni {
            // When GroupUpdateSource was introduced, the _only_ way to have
            // a Pni (and not an aci) be the source address was when the update
            // came from someone invited by Pni rejecting that invitation.
            // Maybe other cases got added in the future, but if they did they'd
            // not use the legacy address storage, so if we find a legacy address
            // with a Pni, it _must_ be from the pni invite rejection case.
            if isKnownLocalUser() {
                return .localUser(originalSource: .rejectedInviteToPni(pni))
            } else {
                return .rejectedInviteToPni(pni)
            }
        } else if let e164 = address.e164 {
            if isKnownLocalUser() {
                return .localUser(originalSource: .legacyE164(e164))
            } else {
                return .legacyE164(e164)
            }
        } else {
            return .unknown
        }
    }
}
