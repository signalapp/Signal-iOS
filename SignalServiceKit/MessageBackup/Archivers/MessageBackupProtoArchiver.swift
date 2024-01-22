//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {
    public enum ArchiveFrameError: Error {
        public enum ReferencedProtoIdType {
            case recipient(RecipientArchivingContext.Address)
            case thread(ThreadUniqueId)
        }

        case protoSerializationError(Error)
        case fileIOError(Error)

        /// The object we are archiving references another object that should have an id assigned
        /// in the proto, but does not.
        /// e.g. we try to archive a message to a recipient aci, but that aci has no ``MessageBackup.RecipientId``.
        case referencedIdMissing(ReferencedProtoIdType)

        /// An error generating the master key for a group, causing the group to be skipped.
        case groupMasterKeyError(Error)

        /// A contact thread has an invalid or missing address information, causing the
        /// thread to be skipped.
        case contactThreadMissingAddress

        /// A message has an invalid or missing address information, causing the
        /// message to be skipped.
        /// (author for incoming messages, recipient(s) for outgoing messages)
        case invalidMessageAddress

        /// A reaction has an invalid or missing author address information, causing the
        /// reaction to be skipped.
        case invalidReactionAddress

        /// A group update message with no updates actually inside it, which is invalid.
        case emptyGroupUpdate
    }

    /// Note the "multi"; covers the archiving of multiple frames, typically
    /// batched by type.
    public enum ArchiveMultiFrameResult<AppIdType> {
        public struct Error {
            public let objectId: AppIdType
            public let error: ArchiveFrameError
        }

        case success
        /// We managed to write some frames, but failed for others.
        /// Note that some errors _may_ be terminal; the caller should check.
        case partialSuccess([Error])
        /// Catastrophic failure, e.g. we failed to read from the database at all
        /// for an entire category of frame.
        case completeFailure(Swift.Error)
    }

    public enum RestoringFrameError: Error {
        public enum ReferencedProtoId {
            case recipient(RecipientId)
            case chat(ChatId)
        }

        public enum ReferencedDBObjectId {
            case thread(ThreadUniqueId)
            case groupThread(groupId: Data)
        }

        /// Some identifier being referenced was not present earlier in the backup file.
        case identifierNotFound(ReferencedProtoId)
        /// The proto contained invalid or self-contradictory data, e.g an invalid ACI.
        case invalidProtoData
        /// The object being inserted depended on another object that should have been created
        /// earlier but was not.
        /// e.g. a message being inserted needs a TSThread to have been created from the chat.
        case referencedDatabaseObjectNotFound(ReferencedDBObjectId)
        case databaseInsertionFailed(Error)
        /// The contents of the frame are not recognized by any archiver and were ignored.
        case unknownFrameType
        // TODO: remove once all known types are handled.
        case unimplemented
    }

    public enum RestoreFrameResult<ProtoIdType> {
        case success
        /// We managed to restore some part of the frame, meaning it is represented in our database.
        /// For example, we restored a message but dropped some invalid recipients.
        /// Generally restoration of other frames can proceed, but the caller can determine
        /// whether to stop or not based on the specific error(s).
        case partialRestore(ProtoIdType, [RestoringFrameError])
        /// Failure to restore the given frame.
        /// Generally restoration of other frames can proceed, but the caller can determine
        /// whether to stop or not based on the specific error(s).
        case failure(ProtoIdType, [RestoringFrameError])
    }
}

public protocol MessageBackupProtoArchiver {

}

extension MessageBackupProtoArchiver {

    /**
     * Helper function to build a frame and write the proto to the backup file in one action
     * with standard error handling.
     *
     * WARNING: any errors thrown in the ``frameBuilder`` function will become
     * ``MessageBackup.ArchiveFrameError.protoSerializationError``s. The closure
     * should only be used to build the frame proto and any sub protos, and not to capture errors encountered
     * reading the information required to build the proto.
     */
    internal static func writeFrameToStream(
        _ stream: MessageBackupProtoOutputStream,
        frameBuilder: (BackupProtoFrameBuilder) throws -> BackupProtoFrame
    ) -> MessageBackup.ArchiveFrameError? {
        let frame: BackupProtoFrame
        do {
            frame = try frameBuilder(BackupProtoFrame.builder())
        } catch {
            return .protoSerializationError(error)
        }
        switch stream.writeFrame(frame) {
        case .success:
            return nil
        case .fileIOError(let error):
            return .fileIOError(error)
        case .protoSerializationError(let error):
            return .protoSerializationError(error)
        }
    }
}

extension MessageBackup.ArchiveFrameError {

    func asArchiveFramesError<AppIdType>(
        objectId: AppIdType
    ) -> MessageBackup.ArchiveMultiFrameResult<AppIdType>.Error {
        return .init(objectId: objectId, error: self)
    }

}
