//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    public enum ProtoInputStreamReadResult<T> {
        case success(T, moreBytesAvailable: Bool)
        case emptyFinalFrame
        case invalidByteLengthDelimiter
        case protoDeserializationError(Swift.Error)
    }
}

/**
 * Input stream for reading and writing a backup file on disk.
 *
 * The backup file is just a sequence of serialized proto bytes, back to back, delimited by varint
 * byte sizes so we know how much to read into memory to deserialize the next proto.
 * The input stream abstracts over this, and allows callers to just think in terms of "frames",
 * the individual proto objects that we read one at a time.
 */
public protocol MessageBackupProtoInputStream {

    /// Read the single header object at the start of every backup file.
    /// If this header is missing or invalid, the backup should be discarded.
    func readHeader() -> MessageBackup.ProtoInputStreamReadResult<BackupProto_BackupInfo>

    var numberOfReadFrames: UInt64 { get }

    /// Read a the next frame from the backup file.
    func readFrame() -> MessageBackup.ProtoInputStreamReadResult<BackupProto_Frame>

    /// Close the stream. Attempting to read after closing will result in failures.
    func closeFileStream()
}

internal class MessageBackupProtoInputStreamImpl: MessageBackupProtoInputStream {

    private var inputStream: InputStreamable
    private var inputStreamDelegate: StreamDelegate

    internal init(
        inputStream: InputStreamable,
        inputStreamDelegate: StreamDelegate
    ) {
        self.inputStream = inputStream
        self.inputStreamDelegate = inputStreamDelegate
    }

    public private(set) var numberOfReadFrames: UInt64 = 0

    internal func readHeader() -> MessageBackup.ProtoInputStreamReadResult<BackupProto_BackupInfo> {
        return readProto { protoData in
            return try BackupProto_BackupInfo(serializedBytes: protoData)
        }
    }

    internal func readFrame() -> MessageBackup.ProtoInputStreamReadResult<BackupProto_Frame> {
        defer { self.numberOfReadFrames += 1 }
        return readProto { protoData in
            return try BackupProto_Frame(serializedBytes: protoData)
        }
    }

    public func closeFileStream() {
        try? inputStream.close()
    }

    private func readProto<T>(
        _ initializer: (Data) throws -> T
    ) -> MessageBackup.ProtoInputStreamReadResult<T> {
        do {
            let data = try inputStream.read(maxLength: 65_536)
            if data.count == 0 && !inputStream.hasBytesAvailable {
                return .emptyFinalFrame
            } else {
                let protoObject = try initializer(data)
                return .success(protoObject, moreBytesAvailable: inputStream.hasBytesAvailable)
            }
        } catch {
            return .protoDeserializationError(error)
        }
    }
}
