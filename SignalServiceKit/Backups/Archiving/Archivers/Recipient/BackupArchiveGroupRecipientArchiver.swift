//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Archives ``TSGroupThread``s as ``BackupProto_Group`` recipients.
///
/// This is a bit confusing, because ``TSThread`` mostly corresponds to
/// ``BackupProto_Chat``, and there will in fact _also_ be a chat for the group
/// thread. Its just that our group thread contains all the metadata
/// corresponding to both the Chat and Recipient parts of the Backup proto.
public class BackupArchiveGroupRecipientArchiver: BackupArchiveProtoStreamWriter {
    typealias GroupId = BackupArchive.GroupId
    typealias RecipientId = BackupArchive.RecipientId
    typealias RecipientAppId = BackupArchive.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError

    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError

    private let avatarDefaultColorManager: AvatarDefaultColorManager
    private let avatarFetcher: BackupArchiveAvatarFetcher
    private let blockingManager: BackupArchive.Shims.BlockingManager
    private let disappearingMessageConfigStore: DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let profileManager: BackupArchive.Shims.ProfileManager
    private let storyStore: BackupArchiveStoryStore
    private let threadStore: BackupArchiveThreadStore

    public init(
        avatarDefaultColorManager: AvatarDefaultColorManager,
        avatarFetcher: BackupArchiveAvatarFetcher,
        blockingManager: BackupArchive.Shims.BlockingManager,
        disappearingMessageConfigStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        profileManager: BackupArchive.Shims.ProfileManager,
        storyStore: BackupArchiveStoryStore,
        threadStore: BackupArchiveThreadStore,
    ) {
        self.avatarDefaultColorManager = avatarDefaultColorManager
        self.avatarFetcher = avatarFetcher
        self.blockingManager = blockingManager
        self.disappearingMessageConfigStore = disappearingMessageConfigStore
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    func archiveAllGroupRecipients(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.RecipientArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        let blockedGroupIds = Set(blockingManager.blockedGroupIds(tx: context.tx))

        do {
            try context.bencher.wrapEnumeration(
                tx: context.tx,
                enumerationBlock: { tx, block throws(CancellationError) in
                    try enumerateGroups(tx: tx, block: block)
                },
                perEnumerantBlock: { [self] groupRecord, frameBencher -> Bool in
                    archiveGroupThread(
                        groupRecord,
                        blockedGroupIds: blockedGroupIds,
                        stream: stream,
                        frameBencher: frameBencher,
                        context: context,
                        errors: &errors,
                    )

                    return true
                },
            )
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    /// Enumerates GroupRecords; adds a boolean "stop" result.
    private func enumerateGroups(
        tx: DBReadTransaction,
        block: (GroupRecord) throws(CancellationError) -> Bool,
    ) throws(CancellationError) {
        enum StopError: Error {
            case stopError
            case cancellationError(CancellationError)
        }
        do throws(StopError) {
            try GroupStore().enumerateGroups(tx: tx) { (groupRecord) throws(StopError) in
                let result: Bool
                do throws(CancellationError) {
                    result = try block(groupRecord)
                } catch {
                    throw .cancellationError(error)
                }
                guard result else {
                    throw .stopError
                }
            }
        } catch {
            switch error {
            case .cancellationError(let error):
                throw error
            case .stopError:
                break
            }
        }
    }

    /// If true, we should back up this group. If false, it's a group pending
    /// deletion that should be skipped.
    private func isValid(groupProto group: BackupProto_Group) -> Bool {
        return group.blocked || (group.hasSnapshot && !isMissing(groupSnapshot: group.snapshot))
    }

    private func isMissing(groupSnapshot snapshot: BackupProto_Group.GroupSnapshot) -> Bool {
        return snapshot.version == 0 && snapshot.members.isEmpty
    }

    private func archiveGroupThread(
        _ groupRecord: GroupRecord,
        blockedGroupIds: Set<Data>,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.RecipientArchivingContext,
        errors: inout [ArchiveFrameError],
    ) {
        guard let groupId = try? GroupIdentifier(contents: groupRecord.groupId) else {
            // Not a GV2 group.
            return
        }

        let groupPair: (thread: TSGroupThread, model: TSGroupModelV2)?
        if let groupThread = threadStore.fetchThread(forGroupId: groupId, tx: context.tx) {
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                // Also not a GV2 group.
                return
            }
            groupPair = (groupThread, groupModel)
        } else {
            groupPair = nil
        }

        guard let masterKey = groupRecord.masterKey else {
            errors.append(.archiveFrameError(.groupMasterKeyError(OWSGenericError("missing master key"))))
            return
        }

        var group = BackupProto_Group()
        group.masterKey = masterKey.serialize()
        group.blocked = blockedGroupIds.contains(groupId.serialize())
        if let groupPair {
            group.whitelisted = profileManager.isGroupId(
                inProfileWhitelist: groupId.serialize(),
                tx: context.tx,
            )
            do {
                group.hideStory = try storyStore.getOrCreateStoryContextAssociatedData(
                    for: groupPair.thread,
                    context: context,
                ).isHidden
            } catch let error {
                errors.append(.archiveFrameError(.unableToReadStoryContextAssociatedData(error)))
            }
            group.storySendMode = { () -> BackupProto_Group.StorySendMode in
                switch groupPair.thread.storyViewMode {
                case .disabled: return .disabled
                case .explicit, .blockList: return .enabled
                case .default: return .default
                }
            }()
            group.avatarColor = avatarDefaultColorManager.defaultColor(
                useCase: .group(groupId: groupId.serialize()),
                tx: context.tx,
            ).asBackupProtoAvatarColor

            let groupModel = groupPair.model
            let groupMembership = groupModel.groupMembership

            var groupSnapshot = BackupProto_Group.GroupSnapshot()
            groupSnapshot.avatarURL = groupModel.avatarUrlPath ?? ""
            groupSnapshot.version = groupModel.revision
            groupSnapshot.inviteLinkPassword = groupModel.inviteLinkPassword ?? Data()
            groupSnapshot.announcementsOnly = groupModel.isAnnouncementsOnly
            if let groupName = groupModel.groupName?.nilIfEmpty {
                groupSnapshot.title = .buildTitle(groupName)
            }
            if let groupDescription = groupModel.descriptionText?.nilIfEmpty {
                groupSnapshot.description_p = .buildDescriptionText(groupDescription)
            }
            if
                let dmConfiguration = disappearingMessageConfigStore.fetch(for: .thread(groupPair.thread), tx: context.tx),
                dmConfiguration.isEnabled
            {
                let durationSeconds = dmConfiguration.durationSeconds
                groupSnapshot.disappearingMessagesTimer = .buildDisappearingMessageTimer(durationSeconds)
            }
            groupSnapshot.accessControl = groupModel.access.asBackupProtoAccessControl
            groupSnapshot.members = groupMembership.fullMembers.compactMap { address -> BackupProto_Group.Member? in
                guard
                    let aci = address.aci,
                    let role = groupMembership.role(for: address)
                else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams))
                    return nil
                }

                return .build(serviceId: aci, role: role, memberLabel: groupMembership.memberLabel(for: aci))
            }
            groupSnapshot.membersPendingProfileKey = groupMembership.invitedMembers.compactMap { address -> BackupProto_Group.MemberPendingProfileKey? in
                guard
                    let serviceId = address.serviceId,
                    let role = groupMembership.role(for: address),
                    let addedByAci = groupMembership.addedByAci(forInvitedMember: address)
                else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams))
                    return nil
                }

                // iOS doesn't track the timestamp of the invite, so we'll
                // default-populate it.
                var invitedMemberProto = BackupProto_Group.MemberPendingProfileKey()
                invitedMemberProto.addedByUserID = addedByAci.serviceIdBinary
                invitedMemberProto.timestamp = 0
                invitedMemberProto.member = .build(
                    serviceId: serviceId,
                    role: role,
                    memberLabel: nil,
                )
                return invitedMemberProto
            }
            groupSnapshot.membersPendingAdminApproval = groupMembership.requestingMembers.compactMap { address -> BackupProto_Group.MemberPendingAdminApproval? in
                guard let aci = address.aci else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams))
                    return nil
                }

                // iOS doesn't track the timestamp of the request, so we'll
                // default-populate it.
                var memberPendingAdminApproval = BackupProto_Group.MemberPendingAdminApproval()
                memberPendingAdminApproval.userID = aci.serviceIdBinary
                memberPendingAdminApproval.timestamp = 0

                return memberPendingAdminApproval
            }
            groupSnapshot.membersBanned = groupMembership.bannedMembers.map { aci, bannedAtMillis -> BackupProto_Group.MemberBanned in
                var memberBanned = BackupProto_Group.MemberBanned()
                memberBanned.userID = aci.serviceIdBinary
                memberBanned.timestamp = bannedAtMillis

                return memberBanned
            }

            groupSnapshot.terminated = groupModel.isTerminated

            group.snapshot = groupSnapshot
        } else {
            group.snapshot = BackupProto_Group.GroupSnapshot()
        }

        guard isValid(groupProto: group) else {
            return
        }

        let maybeError: ArchiveFrameError? = Self.writeFrameToStream(
            stream,
            frameBencher: frameBencher,
            frameBuilder: {
                var recipient = BackupProto_Recipient()
                let recipientId = context.assignRecipientId(to: .group(GroupId(groupId: groupId.serialize())))
                recipient.id = recipientId.value
                recipient.destination = .group(group)

                var frame = BackupProto_Frame()
                frame.item = .recipient(recipient)
                return frame
            },
        )
        if let maybeError {
            errors.append(maybeError)
        }
    }

    func restoreGroupRecipientProto(
        _ groupProto: BackupProto_Group,
        recipient: BackupProto_Recipient,
        context: BackupArchive.RecipientRestoringContext,
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line,
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, line: line)])
        }

        // MARK: Assemble the group model

        let masterKey: GroupMasterKey
        do {
            masterKey = try GroupMasterKey(contents: groupProto.masterKey)
        } catch {
            return restoreFrameError(.invalidProtoData(.invalidGV2MasterKey))
        }
        let secretParams = failIfThrows {
            return try GroupSecretParams.deriveFromMasterKey(groupMasterKey: masterKey)
        }
        let groupId = failIfThrows {
            return try secretParams.getPublicParams().getGroupIdentifier()
        }
        let groupId2 = GroupId(groupId: groupId.serialize())

        guard groupProto.hasSnapshot else {
            return restoreFrameError(.invalidProtoData(.missingGV2GroupSnapshot))
        }

        var groupRecord = GroupStore().fetchGroupOrInsert(secretParams: secretParams, tx: context.tx)

        let groupSnapshot = groupProto.snapshot
        // TODO: Use `== nil` for this check.
        let isGroupSnapshotMissing = isMissing(groupSnapshot: groupSnapshot)

        var partialErrors = [BackupArchive.RestoreFrameError]()

        if !isGroupSnapshotMissing {
            var groupMembershipBuilder = GroupMembership.Builder()
            var fullGroupMemberAcis = Set<Aci>()
            for fullMember in groupSnapshot.members {
                guard let aci = try? Aci.parseFrom(serviceIdBinary: fullMember.userID) else {
                    return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.Member.self)))
                }
                let role = TSGroupMemberRole(backupProtoRole: fullMember.role)

                groupMembershipBuilder.addFullMember(aci, role: role)
                fullGroupMemberAcis.insert(aci)
            }
            for invitedMember in groupSnapshot.membersPendingProfileKey {
                guard invitedMember.hasMember else {
                    return restoreFrameError(.invalidProtoData(.invitedGV2MemberMissingMemberDetails))
                }
                let memberDetails = invitedMember.member
                guard let serviceId = try? ServiceId.parseFrom(serviceIdBinary: memberDetails.userID) else {
                    return restoreFrameError(.invalidProtoData(.invalidServiceId(protoClass: BackupProto_Group.MemberPendingProfileKey.self)))
                }
                let role = TSGroupMemberRole(backupProtoRole: memberDetails.role)
                guard let addedByAci = try? Aci.parseFrom(serviceIdBinary: invitedMember.addedByUserID) else {
                    return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.MemberPendingProfileKey.self)))
                }

                groupMembershipBuilder.addInvitedMember(
                    serviceId,
                    role: role,
                    addedByAci: addedByAci,
                )
            }
            for requestingMember in groupSnapshot.membersPendingAdminApproval {
                guard let aci = try? Aci.parseFrom(serviceIdBinary: requestingMember.userID) else {
                    return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.MemberPendingAdminApproval.self)))
                }

                groupMembershipBuilder.addRequestingMember(aci)
            }
            for bannedMember in groupSnapshot.membersBanned {
                guard let aci = try? Aci.parseFrom(serviceIdBinary: bannedMember.userID) else {
                    return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.MemberBanned.self)))
                }
                let bannedAtTimestampMillis = bannedMember.timestamp

                groupMembershipBuilder.addBannedMember(
                    aci,
                    bannedAtTimestamp: bannedAtTimestampMillis,
                )
            }

            for member in groupSnapshot.members {
                guard let aci = try? Aci.parseFrom(serviceIdBinary: member.userID) else {
                    return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.Member.self)))
                }
                if !member.labelString.isEmpty {
                    guard
                        member.labelString.lengthOfBytes(using: .utf8) <= 96,
                        member.labelString.count <= 24,
                        member.labelEmoji.lengthOfBytes(using: .utf8) <= 48
                    else {
                        partialErrors.append(.restoreFrameError(.invalidProtoData(.invalidMemberLabel)))
                        continue
                    }
                    let emoji: String? = member.labelEmoji.isEmpty ? nil : member.labelEmoji
                    groupMembershipBuilder.setMemberLabel(label: MemberLabel(label: member.labelString, labelEmoji: emoji), aci: aci)
                }
            }

            var groupModelBuilder = TSGroupModelBuilder(secretParams: secretParams)
            groupModelBuilder.groupV2Revision = groupSnapshot.version
            groupModelBuilder.name = groupSnapshot.extractTitle
            groupModelBuilder.descriptionText = groupSnapshot.extractDescriptionText
            // We'll try and download the avatar later. For now, leave it explicitly missing.
            groupModelBuilder.avatarDataState = .missing
            groupModelBuilder.avatarUrlPath = groupSnapshot.avatarURL.nilIfEmpty
            groupModelBuilder.groupMembership = groupMembershipBuilder.build()
            groupModelBuilder.groupAccess = GroupAccess(backupProtoAccessControl: groupSnapshot.accessControl)
            groupModelBuilder.inviteLinkPassword = groupSnapshot.inviteLinkPassword.nilIfEmpty
            groupModelBuilder.isAnnouncementsOnly = groupSnapshot.announcementsOnly

            if RemoteConfig.current.groupTerminateReceiveEnabled {
                groupModelBuilder.isTerminated = groupSnapshot.terminated
            }

            guard let groupModel: TSGroupModelV2 = try? groupModelBuilder.buildAsV2() else {
                return restoreFrameError(.invalidProtoData(.failedToBuildGV2GroupModel))
            }

            // MARK: Use the group model to create a group thread

            let isStorySendEnabled: Bool? = {
                switch groupProto.storySendMode {
                case .default, .UNRECOGNIZED:
                    // No explicit setting.
                    return nil
                case .disabled:
                    return false
                case .enabled:
                    return true
                }
            }()

            let groupThread: TSGroupThread
            do {
                groupThread = try threadStore.insertGroupThread(
                    groupRecord: &groupRecord,
                    groupModel: groupModel,
                    isStorySendEnabled: isStorySendEnabled,
                    context: context,
                )
            } catch let error {
                return restoreFrameError(.databaseInsertionFailed(error))
            }

            // MARK: Store group properties that live outside the group model

            do {
                try threadStore.insertFullGroupMemberRecords(
                    acis: fullGroupMemberAcis,
                    groupThread: groupThread,
                    context: context,
                )
            } catch let error {
                return restoreFrameError(.databaseInsertionFailed(error))
            }

            if let disappearingMessageTimer = groupSnapshot.extractDisappearingMessageTimer {
                disappearingMessageConfigStore.set(
                    token: .token(
                        forProtoExpireTimerSeconds: disappearingMessageTimer,
                    ),
                    for: groupThread,
                    tx: context.tx,
                )
            }

            if groupProto.whitelisted {
                profileManager.addToWhitelist(groupThread, tx: context.tx)
            }

            if
                groupProto.hasAvatarColor,
                let defaultAvatarColor: AvatarTheme = .from(backupProtoAvatarColor: groupProto.avatarColor)
            {
                do {
                    try avatarDefaultColorManager.persistDefaultColor(
                        defaultAvatarColor,
                        groupId: groupId.serialize(),
                        tx: context.tx,
                    )
                } catch {
                    // Don't fail entirely; colors aren't that important.
                    partialErrors.append(.restoreFrameError(.databaseInsertionFailed(error)))
                }
            }

            if groupProto.hideStory {
                // We only need to actively hide, since unhidden is the default.
                do {
                    try storyStore.createStoryContextAssociatedData(
                        for: groupThread,
                        isHidden: true,
                        context: context,
                    )
                } catch let error {
                    // Don't fail entirely; the story will just be unhidden.
                    partialErrors.append(.restoreFrameError(.databaseInsertionFailed(error)))
                }
            }

            context[groupId2] = groupThread
        }

        if groupProto.blocked {
            blockingManager.addBlockedGroupId(groupId.serialize(), tx: context.tx)
        }

        // MARK: Return successfully!

        context[recipient.recipientId] = .group(groupId2)

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}

// MARK: -

private extension Aes256Key {
    /// Is this profile key comprised of all-zeroes?
    ///
    /// It's possible that other clients may not have a persisted profile key
    /// for a user, and consequently when they build the group snapshot to put
    /// in a backup they'll be unable to populate the profile key for some
    /// members. In those cases, they'll put all-zero data for the profile key
    /// as a sentinel value, and we should not persist it.
    var isAllZeroes: Bool {
        return keyData.allSatisfy { $0 == 0 }
    }
}

// MARK: -

private extension BackupProto_Group.GroupAttributeBlob {
    static func buildTitle(_ title: String) -> BackupProto_Group.GroupAttributeBlob {
        var blob = BackupProto_Group.GroupAttributeBlob()
        blob.content = .title(title)
        return blob
    }

    static func buildDescriptionText(_ descriptionText: String) -> BackupProto_Group.GroupAttributeBlob {
        var blob = BackupProto_Group.GroupAttributeBlob()
        blob.content = .descriptionText(descriptionText)
        return blob
    }

    static func buildDisappearingMessageTimer(_ disappearingMessageDuration: UInt32) -> BackupProto_Group.GroupAttributeBlob {
        var blob = BackupProto_Group.GroupAttributeBlob()
        blob.content = .disappearingMessagesDuration(disappearingMessageDuration)
        return blob
    }
}

private extension BackupProto_Group.GroupSnapshot {
    var extractTitle: String? {
        switch title.content {
        case .title(let title): return title
        case nil, .avatar, .descriptionText, .disappearingMessagesDuration: return nil
        }
    }

    var extractDescriptionText: String? {
        switch description_p.content {
        case .descriptionText(let descriptionText): return descriptionText
        case nil, .title, .avatar, .disappearingMessagesDuration: return nil
        }
    }

    var extractDisappearingMessageTimer: UInt32? {
        switch disappearingMessagesTimer.content {
        case .disappearingMessagesDuration(let disappearingMessageDuration): return disappearingMessageDuration
        case nil, .title, .avatar, .descriptionText: return nil
        }
    }
}

// MARK: -

private extension BackupProto_Group.Member {
    static func build(
        serviceId: ServiceId,
        role: TSGroupMemberRole,
        memberLabel: MemberLabel?,
    ) -> BackupProto_Group.Member {
        // iOS doesn't track the joinedAtRevision, so we'll default-populate it.
        var member = BackupProto_Group.Member()
        member.userID = serviceId.serviceIdBinary
        member.role = role.asBackupProtoRole
        member.joinedAtVersion = 0
        if let labelString = memberLabel?.label {
            member.labelString = labelString
        }
        if let labelEmoji = memberLabel?.labelEmoji {
            member.labelEmoji = labelEmoji
        }
        return member
    }
}

// MARK: -

private extension TSGroupMemberRole {
    init(backupProtoRole: BackupProto_Group.Member.Role) {
        switch backupProtoRole {
        case .unknown, .UNRECOGNIZED:
            // Fallback to normal (default)
            self = .normal
        case .default: self = .normal
        case .administrator: self = .administrator
        }
    }

    var asBackupProtoRole: BackupProto_Group.Member.Role {
        switch self {
        case .normal: return .default
        case .administrator: return .administrator
        }
    }
}

// MARK: -

private extension GroupV2Access {
    init(backupProtoAccessRequired: BackupProto_Group.AccessControl.AccessRequired) {
        switch backupProtoAccessRequired {
        case .unknown, .UNRECOGNIZED: self = .unknown
        case .any: self = .any
        case .member: self = .member
        case .administrator: self = .administrator
        case .unsatisfiable: self = .unsatisfiable
        }
    }

    var asBackupProtoAccessRequired: BackupProto_Group.AccessControl.AccessRequired {
        switch self {
        case .unknown: return .unknown
        case .any: return .any
        case .member: return .member
        case .administrator: return .administrator
        case .unsatisfiable: return .unsatisfiable
        }
    }
}

private extension GroupAccess {
    convenience init(backupProtoAccessControl: BackupProto_Group.AccessControl) {
        self.init(
            members: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.members),
            attributes: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.attributes),
            addFromInviteLink: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.addFromInviteLink),
            memberLabels: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.memberLabel),
        )
    }

    var asBackupProtoAccessControl: BackupProto_Group.AccessControl {
        var accessControl = BackupProto_Group.AccessControl()
        accessControl.attributes = attributes.asBackupProtoAccessRequired
        accessControl.members = members.asBackupProtoAccessRequired
        accessControl.addFromInviteLink = addFromInviteLink.asBackupProtoAccessRequired
        accessControl.memberLabel = memberLabels.asBackupProtoAccessRequired
        return accessControl
    }
}
