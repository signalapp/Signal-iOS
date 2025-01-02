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
public class MessageBackupGroupRecipientArchiver: MessageBackupProtoArchiver {
    typealias GroupId = MessageBackup.GroupId
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<RecipientId>

    private let avatarFetcher: MessageBackupAvatarFetcher
    private let disappearingMessageConfigStore: DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let storyStore: MessageBackupStoryStore
    private let threadStore: MessageBackupThreadStore

    private var logger: MessageBackupLogger { .shared }

    public init(
        avatarFetcher: MessageBackupAvatarFetcher,
        disappearingMessageConfigStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        profileManager: MessageBackup.Shims.ProfileManager,
        storyStore: MessageBackupStoryStore,
        threadStore: MessageBackupThreadStore
    ) {
        self.avatarFetcher = avatarFetcher
        self.disappearingMessageConfigStore = disappearingMessageConfigStore
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    func archiveAllGroupRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        do {
            try threadStore.enumerateGroupThreads(context: context) { groupThread in
                try Task.checkCancellation()
                autoreleasepool {
                    self.archiveGroupThread(
                        groupThread,
                        stream: stream,
                        context: context,
                        errors: &errors
                    )
                }

                return true
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            // The enumeration of threads failed, not the processing of one single thread.
            return .completeFailure(.fatalArchiveError(.threadIteratorError(error)))
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    private func archiveGroupThread(
        _ groupThread: TSGroupThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveFrameError]
    ) {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            logger.warn("Skipping archive of V1 group.")
            return
        }

        let groupId = GroupId(groupModel: groupModel)
        let groupMembership = groupModel.groupMembership

        let groupAppId: RecipientAppId = .group(groupId)

        let groupMasterKey: Data
        do {
            let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupModel.secretParamsData))
            groupMasterKey = try groupSecretParams.getMasterKey().serialize().asData
        } catch {
            errors.append(.archiveFrameError(.groupMasterKeyError(error), groupAppId))
            return
        }

        var group = BackupProto_Group()
        group.masterKey = groupMasterKey
        group.whitelisted = profileManager.isThread(
            inProfileWhitelist: groupThread, tx: context.tx
        )
        do {
            group.hideStory = try storyStore.getOrCreateStoryContextAssociatedData(
                for: groupThread,
                context: context
            ).isHidden
        } catch let error {
            errors.append(.archiveFrameError(.unableToReadStoryContextAssociatedData(error), groupAppId))
        }
        group.storySendMode = { () -> BackupProto_Group.StorySendMode in
            switch groupThread.storyViewMode {
            case .disabled: return .disabled
            case .explicit, .blockList: return .enabled
            case .default: return .default
            }
        }()
        group.snapshot = { () -> BackupProto_Group.GroupSnapshot in
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
                let dmConfiguration = disappearingMessageConfigStore.fetch(for: .thread(groupThread), tx: context.tx),
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
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams, groupAppId))
                    return nil
                }

                return .build(serviceId: aci, role: role)
            }
            groupSnapshot.membersPendingProfileKey = groupMembership.invitedMembers.compactMap { address -> BackupProto_Group.MemberPendingProfileKey? in
                guard
                    let serviceId = address.serviceId,
                    let role = groupMembership.role(for: address),
                    let addedByAci = groupMembership.addedByAci(forInvitedMember: address)
                else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams, groupAppId))
                    return nil
                }

                // iOS doesn't track the timestamp of the invite, so we'll
                // default-populate it.
                var invitedMemberProto = BackupProto_Group.MemberPendingProfileKey()
                invitedMemberProto.addedByUserID = addedByAci.serviceIdBinary.asData
                invitedMemberProto.timestamp = 0
                invitedMemberProto.member = .build(
                    serviceId: serviceId,
                    role: role
                )
                return invitedMemberProto
            }
            groupSnapshot.membersPendingAdminApproval = groupMembership.requestingMembers.compactMap { address -> BackupProto_Group.MemberPendingAdminApproval? in
                guard let aci = address.aci else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams, groupAppId))
                    return nil
                }

                // iOS doesn't track the timestamp of the request, so we'll
                // default-populate it.
                var memberPendingAdminApproval = BackupProto_Group.MemberPendingAdminApproval()
                memberPendingAdminApproval.userID = aci.serviceIdBinary.asData
                memberPendingAdminApproval.timestamp = 0

                return memberPendingAdminApproval
            }
            groupSnapshot.membersBanned = groupMembership.bannedMembers.map { aci, bannedAtMillis -> BackupProto_Group.MemberBanned in
                var memberBanned = BackupProto_Group.MemberBanned()
                memberBanned.userID = aci.serviceIdBinary.asData
                memberBanned.timestamp = bannedAtMillis

                return memberBanned
            }

            return groupSnapshot
        }()

        Self.writeFrameToStream(
            stream,
            objectId: groupAppId,
            frameBuilder: {
                var recipient = BackupProto_Recipient()
                let recipientId = context.assignRecipientId(to: groupAppId)
                recipient.id = recipientId.value
                recipient.destination = .group(group)

                var frame = BackupProto_Frame()
                frame.item = .recipient(recipient)
                return frame
            }
        ).map { errors.append($0) }
    }

    func restoreGroupRecipientProto(
        _ groupProto: BackupProto_Group,
        recipient: BackupProto_Recipient,
        context: MessageBackup.RecipientRestoringContext
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, recipient.recipientId, line: line)])
        }

        // MARK: Assemble the group model

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupProto.masterKey)
        } catch {
            return restoreFrameError(.invalidProtoData(.invalidGV2MasterKey))
        }

        guard groupProto.hasSnapshot else {
            return restoreFrameError(.invalidProtoData(.missingGV2GroupSnapshot))
        }
        let groupSnapshot = groupProto.snapshot

        var groupMembershipBuilder = GroupMembership.Builder()
        var fullGroupMemberAcis = Set<Aci>()
        for fullMember in groupSnapshot.members {
            guard let aci = try? Aci.parseFrom(serviceIdBinary: fullMember.userID) else {
                return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.Member.self)))
            }
            guard let role = TSGroupMemberRole(backupProtoRole: fullMember.role) else {
                return restoreFrameError(.invalidProtoData(.unrecognizedGV2MemberRole(protoClass: BackupProto_Group.Member.self)))
            }

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
            guard let role = TSGroupMemberRole(backupProtoRole: memberDetails.role) else {
                return restoreFrameError(.invalidProtoData(.unrecognizedGV2MemberRole(protoClass: BackupProto_Group.MemberPendingProfileKey.self)))
            }
            guard let addedByAci = try? Aci.parseFrom(serviceIdBinary: invitedMember.addedByUserID) else {
                return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto_Group.MemberPendingProfileKey.self)))
            }

            groupMembershipBuilder.addInvitedMember(
                serviceId,
                role: role,
                addedByAci: addedByAci
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
                bannedAtTimestamp: bannedAtTimestampMillis
            )
        }

        var groupModelBuilder = TSGroupModelBuilder()
        groupModelBuilder.groupId = groupContextInfo.groupId
        groupModelBuilder.groupSecretParamsData = groupContextInfo.groupSecretParamsData
        groupModelBuilder.groupsVersion = .V2 // We don't back up V1 groups
        groupModelBuilder.groupV2Revision = groupSnapshot.version
        groupModelBuilder.name = groupSnapshot.extractTitle
        groupModelBuilder.descriptionText = groupSnapshot.extractDescriptionText
        // We'll try and download the avatar later. For now, put in dummy data.
        groupModelBuilder.avatarData = Data()
        groupModelBuilder.avatarUrlPath = groupSnapshot.avatarURL.nilIfEmpty
        groupModelBuilder.groupMembership = groupMembershipBuilder.build()
        groupModelBuilder.groupAccess = GroupAccess(backupProtoAccessControl: groupSnapshot.accessControl)
        groupModelBuilder.inviteLinkPassword = groupSnapshot.inviteLinkPassword.nilIfEmpty
        groupModelBuilder.isAnnouncementsOnly = groupSnapshot.announcementsOnly

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
            groupThread = try threadStore.createGroupThread(
                groupModel: groupModel,
                isStorySendEnabled: isStorySendEnabled,
                context: context
            )
        } catch let error {
            return restoreFrameError(.databaseInsertionFailed(error))
        }

        // MARK: Store group properties that live outside the group model

        do {
            try threadStore.insertFullGroupMemberRecords(
                acis: fullGroupMemberAcis,
                groupThread: groupThread,
                context: context
            )
        } catch let error {
            return restoreFrameError(.databaseInsertionFailed(error))
        }

        if let disappearingMessageTimer = groupSnapshot.extractDisappearingMessageTimer {
            disappearingMessageConfigStore.set(
                token: .token(
                    forProtoExpireTimerSeconds: disappearingMessageTimer
                ),
                for: groupThread,
                tx: context.tx
            )
        }

        if groupProto.whitelisted {
            profileManager.addToWhitelist(groupThread, tx: context.tx)
        }

        var partialErrors = [MessageBackup.RestoreFrameError<RecipientId>]()

        if groupProto.hideStory {
            // We only need to actively hide, since unhidden is the default.
            do {
                try storyStore.createStoryContextAssociatedData(
                    for: groupThread,
                    isHidden: true,
                    context: context
                )
            } catch let error {
                // Don't fail entirely; the story will just be unhidden.
                partialErrors.append(.restoreFrameError(.databaseInsertionFailed(error), recipient.recipientId))
            }
        }

        // MARK: Return successfully!

        let groupId = GroupId(groupModel: groupModel)
        context[recipient.recipientId] = .group(groupId)
        context[groupId] = groupThread

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
        role: TSGroupMemberRole
    ) -> BackupProto_Group.Member {
        // iOS doesn't track the joinedAtRevision, so we'll default-populate it.
        var member = BackupProto_Group.Member()
        member.userID = serviceId.serviceIdBinary.asData
        member.role = role.asBackupProtoRole
        member.joinedAtVersion = 0
        return member
    }
}

// MARK: -

private extension TSGroupMemberRole {
    init?(backupProtoRole: BackupProto_Group.Member.Role) {
        switch backupProtoRole {
        case .unknown, .UNRECOGNIZED: return nil
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
            addFromInviteLink: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.addFromInviteLink)
        )
    }

    var asBackupProtoAccessControl: BackupProto_Group.AccessControl {
        var accessControl = BackupProto_Group.AccessControl()
        accessControl.attributes = attributes.asBackupProtoAccessRequired
        accessControl.members = members.asBackupProtoAccessRequired
        accessControl.addFromInviteLink = addFromInviteLink.asBackupProtoAccessRequired
        return accessControl
    }
}
