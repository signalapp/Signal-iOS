//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension CloudBackup {
    public enum ArchiveFrameError: Error {
        case protoSerializationError(Error)
        case fileIOError(Error)

        /// The object we are archiving references another object that should have an id assigned
        /// in the proto, but does not.
        /// e.g. we try to archive a message to a recipient aci, but that aci has no ``CloudBackup.RecipientId``.
        case referencedIdMissing

        /// An error generating the master key for a group, causing the group to be skipped.
        case groupMasterKeyError(Error)
    }

    /// Note the plural; covers the archiving of multiple frames, typically
    /// batched by type.
    public enum ArchiveFramesResult<AppIdType> {
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
        case identifierNotFound
        /// The proto contained invalid or self-contradictory data, e.g an invalid ACI.
        case invalidProtoData
        /// The object being inserted depended on another object that should have been created
        /// earlier but was not.
        /// e.g. a message being inserted needs a TSThread to have been created from the chat.
        case referencedDatabaseObjectNotFound
        case databaseInsertionFailed(Error)
        /// The contents of the frame are not recognized by any archiver and were ignored.
        case unknownFrameType
    }

    public enum RestoreFrameResult<ProtoIdType> {
        case success
        case failure(ProtoIdType, RestoringFrameError)
    }
}

public protocol CloudBackupProtoArchiver {

}

extension CloudBackupProtoArchiver {

    /**
     * Helper function to build a frame and write the proto to the backup file in one action
     * with standard error handling.
     *
     * WARNING: any errors thrown in the ``frameBuilder`` function will become
     * ``CloudBackup.ArchiveFrameError.protoSerializationError``s. The closure
     * should only be used to build the frame proto and any sub protos, and not to capture errors encountered
     * reading the information required to build the proto.
     */
    internal static func writeFrameToStream(
        _ stream: CloudBackupProtoOutputStream,
        frameBuilder: (BackupProtoFrameBuilder) throws -> BackupProtoFrame
    ) -> CloudBackup.ArchiveFrameError? {
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

extension CloudBackup.ArchiveFrameError {

    func asArchiveFramesError<AppIdType>(
        objectId: AppIdType
    ) -> CloudBackup.ArchiveFramesResult<AppIdType>.Error {
        return .init(objectId: objectId, error: self)
    }

}
