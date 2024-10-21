//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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

    func setGroupUpdateItemsWrapper(_ updateItemsWrapper: PersistableGroupUpdateItemsWrapper) {
        setInfoMessageValue(updateItemsWrapper, forKey: .groupUpdateItems)
    }
}

public extension TSInfoMessage {
    enum GroupUpdateMetadata {
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

    @objc
    func groupUpdateDescription(transaction tx: SDSAnyReadTransaction) -> NSAttributedString {
        let fallback = DisplayableGroupUpdateItem.genericUpdateByUnknownUser.localizedText

        guard
            let localIdentifiers: LocalIdentifiers = DependenciesBridge.shared.tsAccountManager
                .localIdentifiers(tx: tx.asV2Read)
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

    func groupUpdateMetadata(localIdentifiers: LocalIdentifiers) -> GroupUpdateMetadata {
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
                SSKEnvironment.shared.contactManagerRef
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

    /// We only stored this legacy data before we persisted the new ``TSInfoMessage.PersistableGroupUpdateItem``,
    /// so it lives either alongside a model diff or alongside ``TSInfoMessage.LegacyPersistableGroupUpdateItem``.
    private var persistedLegacyUpdateMetadata: GroupUpdateMetadata.UpdateMetadata {
        let source = Self.legacyGroupUpdateSource(infoMessageUserInfoDict: infoMessageUserInfo)
        // We grab this legacy value if we have it; its irrelevant for new persistable
        // update items which know if they are from the local user or not.
        let updaterWasLocalUser: Bool = infoMessageValue(forKey: .legacyUpdaterKnownToBeLocalUser) ?? false

        return GroupUpdateMetadata.UpdateMetadata(
            source: source,
            updaterWasLocalUser: updaterWasLocalUser
        )
    }
}
