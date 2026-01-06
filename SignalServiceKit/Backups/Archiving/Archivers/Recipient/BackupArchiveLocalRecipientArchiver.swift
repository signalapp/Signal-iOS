//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

extension BackupArchive {
    public struct LocalRecipientId: BackupArchive.LoggableId {
        public var typeLogString: String { "Local Recipient" }
        public var idLogString: String { "" }
    }

    public typealias ArchiveLocalRecipientResult = ArchiveSingleFrameResult<RecipientId, LocalRecipientId>
    public typealias RestoreLocalRecipientResult = RestoreFrameResult<RecipientId>
}

/// Archiver for the ``BackupProto_Self`` recipient, a.k.a. the local
/// user author/recipient.  Used as the recipient for the Note To Self chat.
public class BackupArchiveLocalRecipientArchiver: BackupArchiveProtoStreamWriter {
    private static let localRecipientId = BackupArchive.RecipientId(value: 1)

    private let avatarDefaultColorManager: AvatarDefaultColorManager
    private let profileManager: BackupArchive.Shims.ProfileManager
    private let recipientStore: BackupArchiveRecipientStore

    public init(
        avatarDefaultColorManager: AvatarDefaultColorManager,
        profileManager: BackupArchive.Shims.ProfileManager,
        recipientStore: BackupArchiveRecipientStore,
    ) {
        self.avatarDefaultColorManager = avatarDefaultColorManager
        self.profileManager = profileManager
        self.recipientStore = recipientStore
    }

    /// Archive the local recipient.
    func archiveLocalRecipient(
        stream: BackupArchiveProtoOutputStream,
        bencher: BackupArchive.Bencher,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> BackupArchive.ArchiveLocalRecipientResult {
        return bencher.processFrame { frameBencher in
            let defaultAvatarColor: AvatarTheme
            if let localRecipient = recipientStore.fetchRecipient(localIdentifiers: localIdentifiers, tx: tx) {
                defaultAvatarColor = avatarDefaultColorManager.defaultColor(
                    useCase: .contact(recipient: localRecipient),
                    tx: tx,
                )
            } else {
                defaultAvatarColor = avatarDefaultColorManager.defaultColor(
                    useCase: .contactWithoutRecipient(address: localIdentifiers.aciAddress),
                    tx: tx,
                )
            }

            let error = Self.writeFrameToStream(
                stream,
                objectId: BackupArchive.LocalRecipientId(),
                frameBencher: frameBencher,
            ) {
                var selfRecipient = BackupProto_Self()
                selfRecipient.avatarColor = defaultAvatarColor.asBackupProtoAvatarColor

                var recipient = BackupProto_Recipient()
                recipient.id = Self.localRecipientId.value
                recipient.destination = .self_p(selfRecipient)

                var frame = BackupProto_Frame()
                frame.item = .recipient(recipient)
                return frame
            }

            if let error {
                return .failure(error)
            } else {
                return .success(Self.localRecipientId)
            }
        }
    }

    func fetchLocalRecipientRowId(
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> SignalRecipient.RowId? {
        return recipientStore.fetchRecipient(localIdentifiers: localIdentifiers, tx: tx)?.id
    }

    /// Restore a single ``BackupProto/Recipient`` frame for the local recipient.
    public func restoreSelfRecipient(
        _ selfRecipientProto: BackupProto_Self,
        recipient: BackupProto_Recipient,
        context: BackupArchive.RecipientRestoringContext,
    ) -> BackupArchive.RestoreLocalRecipientResult {
        context[recipient.recipientId] = .localAddress

        var localSignalRecipient: SignalRecipient
        do throws(GRDB.DatabaseError) {
            localSignalRecipient = try SignalRecipient.insertRecord(
                aci: context.localIdentifiers.aci,
                phoneNumber: E164(context.localIdentifiers.phoneNumber),
                pni: context.localIdentifiers.pni,
                tx: context.tx,
            )
            recipientStore.didInsertRecipient(localSignalRecipient, tx: context.tx)
        } catch {
            return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipient.recipientId)])
        }

        context.localSignalRecipientRowId = localSignalRecipient.id

        if
            selfRecipientProto.hasAvatarColor,
            let defaultColor: AvatarTheme = .from(backupProtoAvatarColor: selfRecipientProto.avatarColor)
        {
            do {
                try avatarDefaultColorManager.persistDefaultColor(
                    defaultColor,
                    recipientRowId: localSignalRecipient.id,
                    tx: context.tx,
                )
            } catch {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipient.recipientId)])
            }
        }

        profileManager.addRecipientToProfileWhitelist(
            &localSignalRecipient,
            tx: context.tx,
        )

        return .success
    }
}
