//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {

    public struct RecipientId: Hashable {
        let value: UInt64

        public init(value: UInt64) {
            self.value = value
        }

        fileprivate init(recipient: BackupProto_Recipient) {
            self.init(value: recipient.id)
        }

        fileprivate init(chat: BackupProto_Chat) {
            self.init(value: chat.recipientID)
        }

        fileprivate init(chatItem: BackupProto_ChatItem) {
            self.init(value: chatItem.authorID)
        }

        fileprivate init(reaction: BackupProto_Reaction) {
            self.init(value: reaction.authorID)
        }

        fileprivate init(quote: BackupProto_Quote) {
            self.init(value: quote.authorID)
        }

        fileprivate init(sendStatus: BackupProto_SendStatus) {
            self.init(value: sendStatus.recipientID)
        }

        fileprivate init(adHocCall: BackupProto_AdHocCall) {
            self.init(value: adHocCall.recipientID)
        }
    }

    public struct GroupId: Hashable, MessageBackupLoggableId {
        let value: Data

        init(groupModel: TSGroupModel) {
            self.value = groupModel.groupId
        }

        public var typeLogString: String { "Group" }
        public var idLogString: String { value.base64EncodedString() }
    }

    public struct DistributionId: Hashable {

        let value: UUID
        let isMyStoryId: Bool

        init(_ value: UUID) {
            self.value = value

            /// The same hardcoded My Story UUID (all 0's) is shared across clients.
            /// We use the uuid ("distributionId") encoded into the backup proto to determine if this is
            /// "My Story" or not. The same mechanism of shared all-0s-UUID is used in StorageService.
            /// Check, though, that the value didn't drift just in case.
            owsAssertBeta(
                TSPrivateStoryThread.myStoryUniqueId == "00000000-0000-0000-0000-000000000000",
                "My Story hardcoded id drifted; legacy backups may now be invalid"
            )
            self.isMyStoryId = value.uuidString == TSPrivateStoryThread.myStoryUniqueId
        }

        init?(distributionListItem: BackupProto_DistributionListItem) {
            guard let uuid = UUID(data: distributionListItem.distributionID) else {
                return nil
            }
            self.init(uuid)
        }

        init?(storyThread: TSPrivateStoryThread) {
            guard
                let uuidData = storyThread.distributionListIdentifier,
                let uuid = UUID(data: uuidData)
            else {
                return nil
            }
            self.init(uuid)
        }
    }

    /**
     * As we go archiving recipients, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``BackupRecipientId`` to each ``SignalRecipient`` as we
     * insert them. Later, when we create the ``BackupProto_Chat`` corresponding to the ``TSContactThread``
     * for that recipient, we will need to add the corresponding ``BackupRecipientId``, which we look up
     * using the contact's Aci/Pni/e164, from the map this context keeps.
     */
    public class RecipientArchivingContext: ArchivingContext {
        public enum Address {
            case releaseNotesChannel
            case contact(ContactAddress)
            case group(GroupId)
            case distributionList(DistributionId)
            case callLink(CallLinkRecordId)
        }

        let localRecipientId: RecipientId
        let localIdentifiers: LocalIdentifiers

        private var currentRecipientId: RecipientId
        private var releaseNotesChannelRecipientId: RecipientId?
        private let groupIdMap = SharedMap<GroupId, RecipientId>()
        private let distributionIdMap = SharedMap<DistributionId, RecipientId>()
        private let contactAciMap = SharedMap<Aci, RecipientId>()
        private let contactPniMap = SharedMap<Pni, RecipientId>()
        private let contactE164ap = SharedMap<E164, RecipientId>()
        private let callLinkIdMap = SharedMap<CallLinkRecordId, RecipientId>()

        init(
            backupPurpose: MessageBackupPurpose,
            currentBackupAttachmentUploadEra: String?,
            backupAttachmentUploadManager: BackupAttachmentUploadManager,
            localIdentifiers: LocalIdentifiers,
            localRecipientId: RecipientId,
            tx: DBWriteTransaction
        ) {
            self.localIdentifiers = localIdentifiers
            self.localRecipientId = localRecipientId

            // Start after the local recipient id.
            currentRecipientId = RecipientId(value: localRecipientId.value + 1)

            // Also insert the local identifiers, just in case we try and look
            // up the local recipient by .contact enum case.
            contactAciMap[localIdentifiers.aci] = localRecipientId
            if let pni = localIdentifiers.pni {
                contactPniMap[pni] = localRecipientId
            }
            if let e164 = E164(localIdentifiers.phoneNumber) {
                contactE164ap[e164] = currentRecipientId
            }

            super.init(
                backupPurpose: backupPurpose,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
                tx: tx
            )
        }

        func assignRecipientId(to address: Address) -> RecipientId {
            defer {
                currentRecipientId = RecipientId(value: currentRecipientId.value + 1)
            }
            switch address {
            case .releaseNotesChannel:
                releaseNotesChannelRecipientId = currentRecipientId
            case .group(let groupId):
                groupIdMap[groupId] = currentRecipientId
            case .distributionList(let distributionId):
                distributionIdMap[distributionId] = currentRecipientId
            case .contact(let contactAddress):
                // Create mappings for every identifier we know about
                if let aci = contactAddress.aci {
                    contactAciMap[aci] = currentRecipientId
                }
                if let pni = contactAddress.pni {
                    contactPniMap[pni] = currentRecipientId
                }
                if let e164 = contactAddress.e164 {
                    contactE164ap[e164] = currentRecipientId
                }
            case .callLink(let callLinkId):
                callLinkIdMap[callLinkId] = currentRecipientId
            }
            return currentRecipientId
        }

        subscript(_ address: Address) -> RecipientId? {
            // swiftlint:disable:next implicit_getter
            get {
                switch address {
                case .releaseNotesChannel:
                    return releaseNotesChannelRecipientId
                case .group(let groupId):
                    return groupIdMap[groupId]
                case .distributionList(let distributionId):
                    return distributionIdMap[distributionId]
                case .contact(let contactAddress):
                    // Go down identifiers in priority order, return the first we have.
                    if let aci = contactAddress.aci {
                        return contactAciMap[aci]
                    } else if let e164 = contactAddress.e164 {
                        return contactE164ap[e164]
                    } else if let pni = contactAddress.pni {
                        return contactPniMap[pni]
                    } else {
                        return nil
                    }
                case .callLink(let callLinkId):
                    return callLinkIdMap[callLinkId]
                }
            }
        }
    }

    public class RecipientRestoringContext: RestoringContext {
        public enum Address {
            case localAddress
            case releaseNotesChannel
            case contact(ContactAddress)
            case group(GroupId)
            case distributionList(DistributionId)
            case callLink(CallLinkRecordId)
        }

        let localIdentifiers: LocalIdentifiers

        private let map = SharedMap<RecipientId, Address>()
        /// We create TSGroupThread (and GroupModel) when we restore the Recipient, NOT the Chat.
        /// By comparison, TSContactThread is created when we restore the Chat frame.
        /// We cache the TSGroupThread here to avoid fetching later when we do restore the Chat.
        private let groupThreadCache = SharedMap<GroupId, TSGroupThread>()
        private let callLinkRecordCache = SharedMap<CallLinkRecordId, CallLinkRecord>()

        init(
            localIdentifiers: LocalIdentifiers,
            tx: DBWriteTransaction
        ) {
            self.localIdentifiers = localIdentifiers
            super.init(tx: tx)
        }

        subscript(_ id: RecipientId) -> Address? {
            get { map[id] }
            set(newValue) { map[id] = newValue }
        }

        subscript(_ id: GroupId) -> TSGroupThread? {
            get { groupThreadCache[id] }
            set(newValue) { groupThreadCache[id] = newValue }
        }

        subscript(_ id: CallLinkRecordId) -> CallLinkRecord? {
            get { callLinkRecordCache[id] }
            set(newValue) { callLinkRecordCache[id] = newValue }
        }

        func allRecipientIds() -> Dictionary<RecipientId, Address>.Keys {
            return map.keys
        }

        // MARK: Post-Frame Restore

        public struct PostFrameRestoreActions {
            /// A `TSInfoMessage` indicating a contact is hidden should be
            /// inserted for the `SignalRecipient` with the given proto ID.
            ///
            /// We always want some in-chat indication that a hidden contact is,
            /// in fact, hidden. However, that "hidden" state is stored on a
            /// `Contact`, with no related `ChatItem`. Consequently, when we
            /// encounter a hidden `Contact` frame, we'll track that we should,
            /// after all other frames are restored, insert an in-chat message
            /// that the contact is hidden.
            var insertContactHiddenInfoMessage: Bool
        }

        /// Represents actions that should be taken after all `Frame`s have been restored.
        private(set) var postFrameRestoreActions = SharedMap<RecipientId, PostFrameRestoreActions>()

        func setNeedsPostRestoreContactHiddenInfoMessage(recipientId: RecipientId) {
            postFrameRestoreActions[recipientId] = PostFrameRestoreActions(insertContactHiddenInfoMessage: true)
        }
    }
}

extension MessageBackup.RecipientId: MessageBackupLoggableId {
    public var typeLogString: String { "BackupProto_Recipient" }

    public var idLogString: String { "\(self.value)" }
}

extension MessageBackup.RecipientArchivingContext.Address: MessageBackupLoggableId {
    public var typeLogString: String {
        switch self {
        case .releaseNotesChannel:
            return "ReleaseNotesChannel_Type"
        case .contact(let address):
            return address.typeLogString
        case .group:
            return "TSGroupThread"
        case .distributionList:
            return "TSPrivateStoryThread"
        case .callLink:
            return "CallLinkRecord"
        }
    }

    public var idLogString: String {
        switch self {
        case .releaseNotesChannel:
            return "ReleaseNotesChannel_ID"
        case .contact(let contactAddress):
            return contactAddress.idLogString
        case .group(let groupId):
            // Rely on the scrubber to scrub the id.
            return groupId.idLogString
        case .distributionList(let distributionId):
            return distributionId.value.uuidString
        case .callLink(let callLinkRecordId):
            return callLinkRecordId.idLogString
        }
    }
}

extension BackupProto_Recipient {

    public var recipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(recipient: self)
    }
}

extension BackupProto_Chat {

    public var typedRecipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(chat: self)
    }
}

extension BackupProto_ChatItem {

    public var authorRecipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(chatItem: self)
    }
}

extension BackupProto_Reaction {

    public var authorRecipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(reaction: self)
    }
}

extension BackupProto_Quote {

    public var authorRecipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(quote: self)
    }
}

extension BackupProto_SendStatus {

    public var destinationRecipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(sendStatus: self)
    }
}

extension BackupProto_AdHocCall {

    public var callLinkRecipientId: MessageBackup.RecipientId {
        return MessageBackup.RecipientId(adHocCall: self)
    }
}
