//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {
    public enum ProtoInputStreamReadResult<T> {
        case success(T, moreBytesAvailable: Bool)
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
    func readHeader() -> MessageBackup.ProtoInputStreamReadResult<BackupProtoBackupInfo>

    /// Read a the next frame from the backup file.
    func readFrame() -> MessageBackup.ProtoInputStreamReadResult<BackupProtoFrame>

    /// Close the stream. Attempting to read after closing will result in failures.
    func closeFileStream()
}

internal class MessageBackupProtoInputStreamImpl: MessageBackupProtoInputStream {

    private var inputStream: InputStream
    private var streamRunloop: RunLoop
    private var inputStreamDelegate: StreamDelegate

    internal init(
        inputStream: InputStream,
        streamRunloop: RunLoop,
        inputStreamDelegate: StreamDelegate
    ) {
        self.inputStream = inputStream
        self.streamRunloop = streamRunloop
        self.inputStreamDelegate = inputStreamDelegate
    }

    internal func readHeader() -> MessageBackup.ProtoInputStreamReadResult<BackupProtoBackupInfo> {
        return readProto(BackupProtoBackupInfo.init(serializedData:))
    }

    internal func readFrame() -> MessageBackup.ProtoInputStreamReadResult<BackupProtoFrame> {
        return readProto(BackupProtoFrame.init(serializedData:))
    }

    public func closeFileStream() {
        inputStream.remove(from: streamRunloop, forMode: .default)
        inputStream.close()
    }

    private func readProto<T>(
        _ initializer: (Data) throws -> T
    ) -> MessageBackup.ProtoInputStreamReadResult<T> {
        guard let protoByteLengthRaw = decodeVarint() else {
            return .invalidByteLengthDelimiter
        }
        let protoByteLength = Int(protoByteLengthRaw)
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: protoByteLength)
        let actualByteLength = inputStream.read(bytes, maxLength: protoByteLength)
        guard actualByteLength == protoByteLength else {
            return .invalidByteLengthDelimiter
        }
        let protoBytes = Data(bytes: bytes, count: protoByteLength)
        do {
            let protoObject = try initializer(protoBytes)
            return .success(protoObject, moreBytesAvailable: inputStream.hasBytesAvailable)
        } catch {
            return .protoDeserializationError(error)
        }
    }

    /// Private: Parse the next raw varint from the input.
    ///
    /// Based on SwiftProtobuf.BinaryDecoder.decodeVarint()
    private func decodeVarint() -> UInt64? {
        let nextByte = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        inputStream.read(nextByte, maxLength: 1)
        var c = nextByte[0]
        if c & 0x80 == 0 {
            return UInt64(c)
        }
        var value = UInt64(c & 0x7f)
        var shift = UInt64(7)
        while true {
            if !inputStream.hasBytesAvailable || shift > 63 {
                return nil
            }
            inputStream.read(nextByte, maxLength: 1)
            c = nextByte[0]
            value |= UInt64(c & 0x7f) << shift
            if c & 0x80 == 0 {
                return value
            }
            shift += 7
        }
    }
}
