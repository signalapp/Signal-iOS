//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension BackupArchive {
    public protocol LoggableId {
        /// The type, e.g. "TSInteraction" or "ChatItemProto"
        var typeLogString: String { get }

        /// The identifier, scoped to the type, e.g. TSInteraction.uniqueId
        var idLogString: String { get }
    }

    public struct BackupInfoId: LoggableId {
        init() {}

        public var typeLogString: String = "BackupProto_BackupInfo"
        public var idLogString: String = "info"
    }

    /// Represents the result of archiving a single frame.
    public enum ArchiveSingleFrameResult<SuccessType, AppIdType: LoggableId> {
        case success(SuccessType)
        case failure(ArchiveFrameError<AppIdType>)
    }

    /// Represents the result of archiving multiple frames of the same type at
    /// once.
    public enum ArchiveMultiFrameResult<AppIdType: LoggableId> {
        case success
        /// We managed to write some frames, but failed for others.
        /// Note that some errors _may_ be terminal; the caller should check.
        case partialSuccess([ArchiveFrameError<AppIdType>])
        /// Catastrophic failure, e.g. we failed to read from the database at all
        /// for an entire category of frame.
        case completeFailure(FatalArchivingError)
    }

    /// Represents the result of restoring a single frame.
    /// - Note
    /// Frames are always restored individually.
    public enum RestoreFrameResult<ProtoIdType: LoggableId> {
        case success
        /// There was an unrecognized enum (or oneOf) for which we skip restoring this frame
        /// but we should proceed restoring other frames.
        case unrecognizedEnum(UnrecognizedEnumError)
        /// We managed to restore some part of the frame, meaning it is represented in our database.
        /// For example, we restored a message but dropped some invalid recipients.
        /// Generally restoration of other frames can proceed, but the caller can determine
        /// whether to stop or not based on the specific error(s).
        case partialRestore([RestoreFrameError<ProtoIdType>])
        /// Failure to restore the given frame.
        /// Generally restoration of other frames can proceed, but the caller can determine
        /// whether to stop or not based on the specific error(s).
        case failure([RestoreFrameError<ProtoIdType>])
    }

    public class UnrecognizedEnumError: BackupArchive.LoggableError {

        private let enumType: Any.Type

        init(enumType: Any.Type) {
            self.enumType = enumType
        }

        var typeLogString: String { String(describing: enumType) }
        var idLogString: String { "Unrecognized Enum" }
        var callsiteLogString: String { "" }
        var collapseKey: String? { typeLogString }
        var logLevel: BackupArchive.LogLevel { .warning }
    }
}

// MARK: -

public protocol BackupArchiveProtoStreamWriter {}

extension BackupArchiveProtoStreamWriter {

    /**
     * Helper function to build a frame and write the proto to the backup file in one action
     * with standard error handling.
     */
    static func writeFrameToStream<AppIdType>(
        _ stream: BackupArchiveProtoOutputStream,
        objectId: AppIdType,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        frameBuilder: () -> BackupProto_Frame,
    ) -> BackupArchive.ArchiveFrameError<AppIdType>? {
        let frame = frameBuilder()
        frameBencher.didProcessFrame(frame)
        switch stream.writeFrame(frame) {
        case .success:
            return nil
        case .fileIOError(let error):
            return .archiveFrameError(.fileIOError(error), objectId)
        case .protoSerializationError(let error):
            return .archiveFrameError(.protoSerializationError(error), objectId)
        }
    }
}
