//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/**
 * Archives a group (``TSGroupThread``) as a ``BackupProto.Group``, which is a type of
 * ``BackupProto.Recipient``.
 *
 * This is a bit confusing, because ``TSThread`` mostly corresponds to ``BackupProto.Chat``,
 * and there will in fact _also_ be a ``BackupProto.Chat`` for the group thread. Its just that our
 * ``TSGroupThread`` contains all the metadata from both the Chat and Recipient representations
 * in the proto.
 */
public class MessageBackupGroupRecipientArchiver: MessageBackupRecipientDestinationArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    private let disappearingMessageConfigStore: DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let storyStore: StoryStore
    private let threadStore: ThreadStore

    private var logger: MessageBackupLogger { .shared }

    public init(
        disappearingMessageConfigStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        profileManager: MessageBackup.Shims.ProfileManager,
        storyStore: StoryStore,
        threadStore: ThreadStore
    ) {
        self.disappearingMessageConfigStore = disappearingMessageConfigStore
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    public func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        do {
            try threadStore.enumerateGroupThreads(tx: tx) { groupThread in
                self.archiveGroupThread(
                    groupThread,
                    stream: stream,
                    context: context,
                    errors: &errors,
                    tx: tx
                )

                return true
            }
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
        errors: inout [ArchiveFrameError],
        tx: DBReadTransaction
    ) {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            logger.warn("Skipping archive of V1 group.")
            return
        }

        let groupId = groupModel.groupId
        let groupMembership = groupModel.groupMembership

        let groupAppId: RecipientAppId = .group(groupId)
        let recipientId = context.assignRecipientId(to: groupAppId)

        let groupMasterKey: Data
        let groupPublicKey: Data
        do {
            let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupModel.secretParamsData))
            groupMasterKey = try groupSecretParams.getMasterKey().serialize().asData
            groupPublicKey = try groupSecretParams.getPublicParams().serialize().asData
        } catch {
            errors.append(.archiveFrameError(.groupMasterKeyError(error), groupAppId))
            return
        }

        var group = BackupProto.Group(
            masterKey: groupMasterKey,
            whitelisted: profileManager.isThread(
                inProfileWhitelist: groupThread, tx: tx
            ),
            hideStory: storyStore.getOrCreateStoryContextAssociatedData(
                forGroupThread: groupThread, tx: tx
            ).isHidden,
            storySendMode: { () -> BackupProto.Group.StorySendMode in
                switch groupThread.storyViewMode {
                case .disabled: return .DISABLED
                case .explicit, .blockList: return .ENABLED
                case .default: return .DEFAULT
                }
            }()
        )
        group.snapshot = { () -> BackupProto.Group.GroupSnapshot in
            var groupSnapshot = BackupProto.Group.GroupSnapshot(
                publicKey: groupPublicKey,
                avatarUrl: groupModel.avatarUrlPath ?? "",
                version: groupModel.revision,
                inviteLinkPassword: groupModel.inviteLinkPassword ?? Data(),
                announcementsOnly: groupModel.isAnnouncementsOnly
            )
            groupSnapshot.title = groupModel.groupName?.nilIfEmpty.map { .buildTitle($0) }
            groupSnapshot.descriptionText = groupModel.descriptionText?.nilIfEmpty.map { .buildDescriptionText($0) }
            groupSnapshot.disappearingMessagesTimer = { () -> BackupProto.Group.GroupAttributeBlob? in
                let durationSeconds = disappearingMessageConfigStore.durationSeconds(for: groupThread, tx: tx)
                return durationSeconds > 0 ? .buildDisappearingMessageTimer(durationSeconds) : nil
            }()
            groupSnapshot.accessControl = groupModel.access.asBackupProtoAccessControl
            groupSnapshot.members = groupMembership.fullMembers.compactMap { address -> BackupProto.Group.Member? in
                guard
                    let aci = address.aci,
                    let role = groupMembership.role(for: address),
                    let profileKey = profileManager.getProfileKeyData(for: address, tx: tx)
                else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams, groupAppId))
                    return nil
                }

                return .build(serviceId: aci, role: role, profileKeyData: profileKey)
            }
            groupSnapshot.membersPendingProfileKey = groupMembership.invitedMembers.compactMap { address -> BackupProto.Group.MemberPendingProfileKey? in
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
                var invitedMemberProto = BackupProto.Group.MemberPendingProfileKey(
                    addedByUserId: addedByAci.serviceIdBinary.asData,
                    timestamp: 0
                )
                invitedMemberProto.member = .build(
                    serviceId: serviceId,
                    role: role,
                    profileKeyData: nil
                )
                return invitedMemberProto
            }
            groupSnapshot.membersPendingAdminApproval = groupMembership.requestingMembers.compactMap { address -> BackupProto.Group.MemberPendingAdminApproval? in
                guard
                    let aci = address.aci,
                    let profileKey = profileManager.getProfileKeyData(for: address, tx: tx)
                else {
                    errors.append(.archiveFrameError(.missingRequiredGroupMemberParams, groupAppId))
                    return nil
                }

                // iOS doesn't track the timestamp of the request, so we'll
                // default-populate it.
                return BackupProto.Group.MemberPendingAdminApproval(
                    userId: aci.serviceIdBinary.asData,
                    profileKey: profileKey,
                    timestamp: 0
                )
            }
            groupSnapshot.membersBanned = groupMembership.bannedMembers.map { aci, bannedAtMillis -> BackupProto.Group.MemberBanned in
                return BackupProto.Group.MemberBanned(
                    userId: aci.serviceIdBinary.asData,
                    timestamp: bannedAtMillis
                )
            }

            return groupSnapshot
        }()

        Self.writeFrameToStream(
            stream,
            objectId: groupAppId,
            frameBuilder: {
                var recipient = BackupProto.Recipient(id: recipientId.value)
                recipient.destination = .group(group)

                var frame = BackupProto.Frame()
                frame.item = .recipient(recipient)
                return frame
            }
        ).map { errors.append($0) }
    }

    static func canRestore(_ recipient: BackupProto.Recipient) -> Bool {
        switch recipient.destination {
        case .group:
            return true
        case nil, .contact, .distributionList, .selfRecipient, .releaseNotes, .callLink:
            return false
        }
    }

    public func restore(
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        let groupProto: BackupProto.Group
        switch recipient.destination {
        case .group(let backupProtoGroup):
            groupProto = backupProtoGroup
        case nil, .contact, .distributionList, .selfRecipient, .releaseNotes, .callLink:
            return .failure([.restoreFrameError(
                .developerError(OWSAssertionError("Invalid proto for class")),
                recipient.recipientId
            )])
        }

        // MARK: Assemble the group model

        let groupContextInfo: GroupV2ContextInfo
        do {
            let masterKey = groupProto.masterKey

            guard groupsV2.isValidGroupV2MasterKey(masterKey) else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidGV2MasterKey), recipient.recipientId)])
            }

            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        } catch {
            return .failure([.restoreFrameError(.invalidProtoData(.invalidGV2MasterKey), recipient.recipientId)])
        }

        guard let groupSnapshot = groupProto.snapshot else {
            return .failure([.restoreFrameError(.invalidProtoData(.missingGV2GroupSnapshot), recipient.recipientId)])
        }

        var groupMembershipBuilder = GroupMembership.Builder()
        for fullMember in groupSnapshot.members {
            guard let aci = try? Aci.parseFrom(serviceIdBinary: fullMember.userId) else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto.Group.Member.self)), recipient.recipientId)])
            }
            guard let role = TSGroupMemberRole(backupProtoRole: fullMember.role) else {
                return .failure([.restoreFrameError(.invalidProtoData(.unrecognizedGV2MemberRole(protoClass: BackupProto.Group.Member.self)), recipient.recipientId)])
            }

            groupMembershipBuilder.addFullMember(aci, role: role)

            if
                let profileKey = OWSAES256Key(data: fullMember.profileKey),
                !profileKey.isAllZeroes
            {
                profileManager.setProfileKeyIfMissing(
                    profileKey,
                    forAci: aci,
                    localIdentifiers: context.localIdentifiers,
                    tx: tx
                )
            }
        }
        for invitedMember in groupSnapshot.membersPendingProfileKey {
            guard let memberDetails = invitedMember.member else {
                return .failure([.restoreFrameError(.invalidProtoData(.invitedGV2MemberMissingMemberDetails), recipient.recipientId)])
            }
            guard let serviceId = try? ServiceId.parseFrom(serviceIdBinary: memberDetails.userId) else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidServiceId(protoClass: BackupProto.Group.MemberPendingProfileKey.self)), recipient.recipientId)])
            }
            guard let role = TSGroupMemberRole(backupProtoRole: memberDetails.role) else {
                return .failure([.restoreFrameError(.invalidProtoData(.unrecognizedGV2MemberRole(protoClass: BackupProto.Group.MemberPendingProfileKey.self)), recipient.recipientId)])
            }
            guard let addedByAci = try? Aci.parseFrom(serviceIdBinary: invitedMember.addedByUserId) else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto.Group.MemberPendingProfileKey.self)), recipient.recipientId)])
            }

            groupMembershipBuilder.addInvitedMember(
                serviceId,
                role: role,
                addedByAci: addedByAci
            )
        }
        for requestingMember in groupSnapshot.membersPendingAdminApproval {
            guard let aci = try? Aci.parseFrom(serviceIdBinary: requestingMember.userId) else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto.Group.MemberPendingAdminApproval.self)), recipient.recipientId)])
            }
            groupMembershipBuilder.addRequestingMember(aci)

            if
                let profileKey = OWSAES256Key(data: requestingMember.profileKey),
                !profileKey.isAllZeroes
            {
                profileManager.setProfileKeyIfMissing(
                    profileKey,
                    forAci: aci,
                    localIdentifiers: context.localIdentifiers,
                    tx: tx
                )
            }
        }
        for bannedMember in groupSnapshot.membersBanned {
            guard let aci = try? Aci.parseFrom(serviceIdBinary: bannedMember.userId) else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto.Group.MemberBanned.self)), recipient.recipientId)])
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
        groupModelBuilder.avatarData = nil
        groupModelBuilder.avatarUrlPath = groupSnapshot.avatarUrl.nilIfEmpty
        groupModelBuilder.groupMembership = groupMembershipBuilder.build()
        groupModelBuilder.groupAccess = groupSnapshot.accessControl.map(GroupAccess.init(backupProtoAccessControl:))
        groupModelBuilder.inviteLinkPassword = groupSnapshot.inviteLinkPassword.nilIfEmpty
        groupModelBuilder.isAnnouncementsOnly = groupSnapshot.announcementsOnly

        guard let groupModel: TSGroupModelV2 = try? groupModelBuilder.buildAsV2() else {
            return .failure([.restoreFrameError(.invalidProtoData(.failedToBuildGV2GroupModel), recipient.recipientId)])
        }

        // MARK: Use the group model to create a group thread

        let groupThread = threadStore.createGroupThread(
            groupModel: groupModel, tx: tx
        )

        // MARK: Store group properties that live outside the group model

        disappearingMessageConfigStore.set(
            token: .token(
                forProtoExpireTimerSeconds: groupSnapshot.extractDisappearingMessageTimer
            ),
            for: .thread(groupThread),
            tx: tx
        )

        if groupProto.whitelisted {
            profileManager.addToWhitelist(groupThread, tx: tx)
        }

        let isStorySendEnabled: Bool? = {
            switch groupProto.storySendMode {
            case .DEFAULT:
                // No explicit setting.
                return nil
            case .DISABLED:
                return false
            case .ENABLED:
                return true
            }
        }()
        if let isStorySendEnabled {
            threadStore.update(
                groupThread: groupThread,
                withStorySendEnabled: isStorySendEnabled,
                updateStorageService: false,
                tx: tx
            )
        }
        if groupProto.hideStory {
            // We only need to actively hide, since unhidden is the default.
            let storyContext = storyStore.getOrCreateStoryContextAssociatedData(
                forGroupThread: groupThread, tx: tx
            )
            storyStore.updateStoryContext(storyContext, isHidden: true, tx: tx)
        }

        if groupModel.avatarUrlPath != nil {
            // [Backups] TODO: Enqueue download of the group avatar.
        }

        // MARK: Return successfully!

        context[recipient.recipientId] = .group(groupModel.groupId)
        return .success
    }
}

// MARK: -

private extension OWSAES256Key {
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

private extension BackupProto.Group.GroupAttributeBlob {
    static func buildTitle(_ title: String) -> BackupProto.Group.GroupAttributeBlob {
        var blob = BackupProto.Group.GroupAttributeBlob()
        blob.content = .title(title)
        return blob
    }

    static func buildDescriptionText(_ descriptionText: String) -> BackupProto.Group.GroupAttributeBlob {
        var blob = BackupProto.Group.GroupAttributeBlob()
        blob.content = .descriptionText(descriptionText)
        return blob
    }

    static func buildDisappearingMessageTimer(_ disappearingMessageDuration: UInt32) -> BackupProto.Group.GroupAttributeBlob {
        var blob = BackupProto.Group.GroupAttributeBlob()
        blob.content = .disappearingMessagesDuration(disappearingMessageDuration)
        return blob
    }
}

private extension BackupProto.Group.GroupSnapshot {
    var extractTitle: String? {
        switch title?.content {
        case .title(let title): return title
        case nil, .avatar, .descriptionText, .disappearingMessagesDuration: return nil
        }
    }

    var extractDescriptionText: String? {
        switch descriptionText?.content {
        case .descriptionText(let descriptionText): return descriptionText
        case nil, .title, .avatar, .disappearingMessagesDuration: return nil
        }
    }

    var extractDisappearingMessageTimer: UInt32? {
        switch disappearingMessagesTimer?.content {
        case .disappearingMessagesDuration(let disappearingMessageDuration): return disappearingMessageDuration
        case nil, .title, .avatar, .descriptionText: return nil
        }
    }
}

// MARK: -

private extension BackupProto.Group.Member {
    static func build(
        serviceId: ServiceId,
        role: TSGroupMemberRole,
        profileKeyData: Data?
    ) -> BackupProto.Group.Member {
        // iOS doesn't track the joinedAtRevision, so we'll default-populate it.
        return BackupProto.Group.Member(
            userId: serviceId.serviceIdBinary.asData,
            role: role.asBackupProtoRole,
            profileKey: profileKeyData ?? Data(),
            joinedAtVersion: 0
        )
    }
}

// MARK: -

private extension TSGroupMemberRole {
    init?(backupProtoRole: BackupProto.Group.Member.Role) {
        switch backupProtoRole {
        case .UNKNOWN: return nil
        case .DEFAULT: self = .normal
        case .ADMINISTRATOR: self = .administrator
        }
    }

    var asBackupProtoRole: BackupProto.Group.Member.Role {
        switch self {
        case .normal: return .DEFAULT
        case .administrator: return .ADMINISTRATOR
        }
    }
}

// MARK: -

private extension GroupV2Access {
    init(backupProtoAccessRequired: BackupProto.Group.AccessControl.AccessRequired) {
        switch backupProtoAccessRequired {
        case .UNKNOWN: self = .unknown
        case .ANY: self = .any
        case .MEMBER: self = .member
        case .ADMINISTRATOR: self = .administrator
        case .UNSATISFIABLE: self = .unsatisfiable
        }
    }

    var asBackupProtoAccessRequired: BackupProto.Group.AccessControl.AccessRequired {
        switch self {
        case .unknown: return .UNKNOWN
        case .any: return .ANY
        case .member: return .MEMBER
        case .administrator: return .ADMINISTRATOR
        case .unsatisfiable: return .UNSATISFIABLE
        }
    }
}

private extension GroupAccess {
    convenience init(backupProtoAccessControl: BackupProto.Group.AccessControl) {
        self.init(
            members: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.members),
            attributes: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.attributes),
            addFromInviteLink: GroupV2Access(backupProtoAccessRequired: backupProtoAccessControl.addFromInviteLink)
        )
    }

    var asBackupProtoAccessControl: BackupProto.Group.AccessControl {
        return BackupProto.Group.AccessControl(
            attributes: attributes.asBackupProtoAccessRequired,
            members: members.asBackupProtoAccessRequired,
            addFromInviteLink: addFromInviteLink.asBackupProtoAccessRequired
        )
    }
}
