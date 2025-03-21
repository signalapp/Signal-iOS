//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

// MARK: -

extension TSGroupThread {
    func update(
        with newGroupModel: TSGroupModel,
        shouldUpdateChatListUi: Bool = true,
        transaction tx: DBWriteTransaction
    ) {
        let didAvatarChange = newGroupModel.avatarHash == groupModel.avatarHash
        let didNameChange = newGroupModel.groupNameOrDefault == groupModel.groupNameOrDefault

        let oldGroupMembers = groupModel.groupMembers

        anyUpdateGroupThread(transaction: tx) { groupThread in
            if let oldGroupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                if let newGroupModelV2 = newGroupModel as? TSGroupModelV2 {
                    owsPrecondition(oldGroupModelV2.revision <= newGroupModelV2.revision)
                } else {
                    owsFail("Cannot downgrade a V2 model to a V1 model!")
                }
            }

            groupThread.groupModel = newGroupModel.copy() as! TSGroupModel
        }

        updateGroupMemberRecords(transaction: tx)
        clearGroupSendEndorsementsIfNeeded(oldGroupMembers: oldGroupMembers, tx: tx)

        SSKEnvironment.shared.databaseStorageRef.touch(
            thread: self,
            shouldReindex: didNameChange,
            tx: tx
        )

        if didAvatarChange {
            tx.addSyncCompletion {
                NotificationCenter.default.postNotificationNameAsync(
                    .TSGroupThreadAvatarChanged,
                    object: self.uniqueId,
                    userInfo: [TSGroupThread_NotificationKey_UniqueId: self.uniqueId]
                )
            }
        }
    }
}

// MARK: -

extension TSGroupThread {
    public var groupIdentifier: GroupIdentifier {
        get throws {
            return try GroupIdentifier(contents: [UInt8](self.groupId))
        }
    }

    public static func fetch(forGroupId groupId: GroupIdentifier, tx: DBReadTransaction) -> TSGroupThread? {
        return fetch(groupId: groupId.serialize().asData, transaction: tx)
    }

    @objc
    func clearGroupSendEndorsementsIfNeeded(oldGroupMembers: [SignalServiceAddress], tx: DBWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
        var oldGroupMembers = Set(oldGroupMembers.compactMap(\.serviceId))
        var newGroupMembers = Set(self.groupModel.groupMembers.compactMap(\.serviceId))
        // We don't have a GSE for ourselves, so ignore our own ACI in this check.
        if let localIdentifiers {
            oldGroupMembers.remove(localIdentifiers.aci)
            newGroupMembers.remove(localIdentifiers.aci)
        }
        if oldGroupMembers != newGroupMembers {
            let groupSendEndorsementStore = DependenciesBridge.shared.groupSendEndorsementStore
            Logger.info("Clearing GSEs in \(self.uniqueId) due to membership change.")
            groupSendEndorsementStore.deleteEndorsements(groupThreadId: self.sqliteRowId!, tx: tx)
        }
    }
}

// MARK: -

public extension TSGroupThread {
    func updateWithStorySendEnabled(
        _ storySendEnabled: Bool,
        transaction: DBWriteTransaction,
        updateStorageService: Bool = true
    ) {
        let wasStorySendEnabled = self.isStorySendExplicitlyEnabled
        updateWithStoryViewMode(storySendEnabled ? .explicit : .disabled, transaction: transaction)

        if updateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: groupModel)
        }

        if !wasStorySendEnabled, storySendEnabled {
            // When enabling after being disabled, always unhide the story context.
            if
                let storyContextAssociatedData = StoryFinder.associatedData(for: self, transaction: transaction),
                storyContextAssociatedData.isHidden
            {
                storyContextAssociatedData.update(
                    updateStorageService: updateStorageService,
                    isHidden: false,
                    transaction: transaction
                )
            }
        }
    }

    var isStorySendExplicitlyEnabled: Bool {
        storyViewMode == .explicit
    }

    func isStorySendEnabled(transaction: DBReadTransaction) -> Bool {
        if isStorySendExplicitlyEnabled { return true }
        return StoryFinder.latestStoryForThread(self, transaction: transaction) != nil
    }
}

// MARK: -

public extension TSThreadStoryViewMode {
    var storageServiceMode: StorageServiceProtoGroupV2RecordStorySendMode {
        switch self {
        case .default:
            return .default
        case .explicit:
            return .enabled
        case .disabled:
            return .disabled
        case .blockList:
            owsFailDebug("Unexpected story mode")
            return .default
        }
    }

    init(storageServiceMode: StorageServiceProtoGroupV2RecordStorySendMode) {
        switch storageServiceMode {
        case .default:
            self = .default
        case .disabled:
            self = .disabled
        case .enabled:
            self = .explicit
        case .UNRECOGNIZED(let value):
            owsFailDebug("Unexpected story mode \(value)")
            self = .default
        }
    }
}

// MARK: -

extension TSGroupThread {
    override open func update(
        withInsertedMessage message: TSInteraction,
        transaction tx: DBWriteTransaction
    ) {
        super.update(withInsertedMessage: message, transaction: tx)

        let senderAddress: SignalServiceAddress? = {
            if message is TSOutgoingMessage {
                return DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress
            } else if let incomingMessage = message as? TSIncomingMessage {
                return incomingMessage.authorAddress
            }

            return nil
        }()

        guard let senderAddress else { return }

        guard let groupMember = TSGroupMember.groupMember(
            for: senderAddress, in: uniqueId, transaction: tx
        ) else {
            owsFailDebug("Unexpectedly missing group member record!")
            return
        }

        groupMember.anyUpdateWith(
            lastInteractionTimestamp: message.timestamp,
            transaction: tx
        )
    }
}

// MARK: - Testable build

#if TESTABLE_BUILD

extension TSGroupThread {

    public static func forUnitTest(
        groupId: UInt8 = 0,
        groupMembers: [SignalServiceAddress] = []
    ) -> TSGroupThread {
        return _forUnitTest(
            groupId: Data(repeating: groupId, count: 32),
            secretParamsData: Data(count: 1),
            groupMembers: groupMembers
        )
    }

    static func forUnitTest(
        masterKey: GroupMasterKey,
        groupMembers: [SignalServiceAddress] = []
    ) -> TSGroupThread {
        let secretParams = try! GroupSecretParams.deriveFromMasterKey(groupMasterKey: masterKey)
        return _forUnitTest(
            groupId: try! secretParams.getPublicParams().getGroupIdentifier().serialize().asData,
            secretParamsData: secretParams.serialize().asData,
            groupMembers: groupMembers
        )
    }

    private static func _forUnitTest(
        groupId: Data,
        secretParamsData: Data,
        groupMembers: [SignalServiceAddress] = []
    ) -> TSGroupThread {
        let groupThreadId = TSGroupThread.defaultThreadId(forGroupId: groupId)
        let groupThread = TSGroupThread(
            grdbId: 1,
            uniqueId: groupThreadId,
            conversationColorNameObsolete: "",
            creationDate: nil,
            editTargetTimestamp: nil,
            isArchivedObsolete: false,
            isMarkedUnreadObsolete: false,
            lastInteractionRowId: 1,
            lastSentStoryTimestamp: nil,
            lastVisibleSortIdObsolete: 0,
            lastVisibleSortIdOnScreenPercentageObsolete: 0,
            mentionNotificationMode: .default,
            messageDraft: nil,
            messageDraftBodyRanges: nil,
            mutedUntilDateObsolete: nil,
            mutedUntilTimestampObsolete: 0,
            shouldThreadBeVisible: true,
            storyViewMode: .default,
            groupModel: TSGroupModelV2(
                groupId: groupId,
                name: "Example Group",
                descriptionText: nil,
                avatarDataState: .missing,
                groupMembership: GroupMembership(membersForTest: groupMembers),
                groupAccess: .defaultForV2,
                revision: 1,
                secretParamsData: secretParamsData,
                avatarUrlPath: nil,
                inviteLinkPassword: nil,
                isAnnouncementsOnly: false,
                isJoinRequestPlaceholder: false,
                wasJustMigrated: false,
                didJustAddSelfViaGroupLink: false,
                addedByAddress: nil
            )
        )
        groupThread.clearRowId()
        return groupThread
    }
}

#endif
