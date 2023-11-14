//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum CloudBackupOutputStreamOpenError: Error {
    case unableToOpenFileStream
}

public enum CloudBackupInputStreamOpenError: Error {
    case fileMissing
    case unableToOpenFileStream
}

public protocol CloudBackupOutputStreamProvider {

    func openOutputFileStream() -> Result<CloudBackupOutputStream, CloudBackupOutputStreamOpenError>

    func openInputFileStream(fileURL: URL) -> Result<CloudBackupInputStream, CloudBackupInputStreamOpenError>
}

public protocol CloudBackupOutputStream {

    func writeHeader(_ header: BackupProtoBackupInfo) throws

    func writeFrame(_ frame: BackupProtoFrame) throws

    // Returns URL of the file written to.
    func closeFileStream() -> URL
}

extension CloudBackup {
    public struct InputStreamReadResult<T> {
        let object: T?
        let moreBytesAvailable: Bool
    }
}

public protocol CloudBackupInputStream {

    func readHeader() throws -> CloudBackup.InputStreamReadResult<BackupProtoBackupInfo>

    func readFrame() throws -> CloudBackup.InputStreamReadResult<BackupProtoFrame>

    func closeFileStream()
}

public class CloudBackupOutputStreamProviderImpl: CloudBackupOutputStreamProvider {

    public init() {}

    public func openOutputFileStream() -> Result<CloudBackupOutputStream, CloudBackupOutputStreamOpenError> {
        let fileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        guard let outputStream = OutputStream(url: fileUrl, append: false) else {
            owsFailDebug("Could not open outputStream.")
            return .failure(.unableToOpenFileStream)
        }
        let outputStreamDelegate = StreamDelegate()
        outputStream.delegate = outputStreamDelegate
        let streamRunloop = RunLoop.current
        outputStream.schedule(in: streamRunloop, forMode: .default)
        outputStream.open()
        guard outputStream.streamStatus == .open else {
            owsFailDebug("Could not open outputStream.")
            return .failure(.unableToOpenFileStream)
        }

        let cloudBackupOutputStream = CloudBackupOutputStreamImpl(
            outputStream: outputStream,
            streamRunloop: streamRunloop,
            outputStreamDelegate: outputStreamDelegate,
            fileURL: fileUrl
        )
        return .success(cloudBackupOutputStream)
    }

    public func openInputFileStream(fileURL: URL) -> Result<CloudBackupInputStream, CloudBackupInputStreamOpenError> {
        guard OWSFileSystem.fileOrFolderExists(url: fileURL) else {
            owsFailDebug("Missing file!")
            return .failure(.fileMissing)
        }
        guard let inputStream = InputStream(url: fileURL) else {
            owsFailDebug("Unable to open input stream")
            return .failure(.unableToOpenFileStream)
        }
        let inputStreamDelegate = StreamDelegate()
        inputStream.delegate = inputStreamDelegate
        let streamRunloop = RunLoop.current
        inputStream.schedule(in: streamRunloop, forMode: .default)
        inputStream.open()
        guard inputStream.streamStatus == .open else {
            owsFailDebug("Could not open input stream.")
            return .failure(.unableToOpenFileStream)
        }

        let cloudBackupInputStream = CloudBackupInputStreamImpl(
            inputStream: inputStream,
            streamRunloop: streamRunloop,
            inputStreamDelegate: inputStreamDelegate
        )
        return .success(cloudBackupInputStream)
    }

    fileprivate class StreamDelegate: NSObject, Foundation.StreamDelegate {
        private let _hadError = AtomicBool(false)
        public var hadError: Bool { _hadError.get() }

        @objc
        public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
            if eventCode == .errorOccurred {
                _hadError.set(true)
            }
        }
    }
}

internal class CloudBackupOutputStreamImpl: OWSChunkedOutputStream, CloudBackupOutputStream {

    private var outputStream: OutputStream
    private var streamRunloop: RunLoop
    private var outputStreamDelegate: StreamDelegate
    private var fileUrl: URL

    internal init(
        outputStream: OutputStream,
        streamRunloop: RunLoop,
        outputStreamDelegate: StreamDelegate,
        fileURL: URL
    ) {
        self.outputStream = outputStream
        self.streamRunloop = streamRunloop
        self.outputStreamDelegate = outputStreamDelegate
        self.fileUrl = fileURL
        super.init(outputStream: outputStream)
    }

    internal func writeHeader(_ header: BackupProtoBackupInfo) throws {
        let bytes = try header.serializedData()
        let byteLength = UInt32(bytes.count)
        try writeVariableLengthUInt32(byteLength)
        try writeData(bytes)
    }

    internal func writeFrame(_ frame: BackupProtoFrame) throws {
        let bytes = try frame.serializedData()
        let byteLength = UInt32(bytes.count)
        try writeVariableLengthUInt32(byteLength)
        try writeData(bytes)
    }

    public func closeFileStream() -> URL {
        outputStream.remove(from: streamRunloop, forMode: .default)
        outputStream.close()
        return fileUrl
    }
}

internal class CloudBackupInputStreamImpl: CloudBackupInputStream {

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

    enum ReadError: Error {
        case invalidByteLengthDelimiter
        case fileTruncated
    }

    internal func readHeader() throws -> CloudBackup.InputStreamReadResult<BackupProtoBackupInfo> {
        return try readProto(BackupProtoBackupInfo.init(serializedData:))
    }

    internal func readFrame() throws -> CloudBackup.InputStreamReadResult<BackupProtoFrame> {
        return try readProto(BackupProtoFrame.init(serializedData:))
    }

    public func closeFileStream() {
        inputStream.remove(from: streamRunloop, forMode: .default)
        inputStream.close()
    }

    private func readProto<T>(
        _ initializer: (Data) throws -> T
    ) throws -> CloudBackup.InputStreamReadResult<T> {
        let protoByteLength = Int(try decodeVarint())
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: protoByteLength)
        let actualByteLength = inputStream.read(bytes, maxLength: protoByteLength)
        guard actualByteLength == protoByteLength else {
            throw ReadError.fileTruncated
        }
        let protoBytes = Data(bytes: bytes, count: protoByteLength)
        let protoObject = try initializer(protoBytes)
        return .init(object: protoObject, moreBytesAvailable: inputStream.hasBytesAvailable)
    }

    /// Private: Parse the next raw varint from the input.
    ///
    /// Based on SwiftProtobuf.BinaryDecoder.decodeVarint()
    private func decodeVarint() throws -> UInt64 {
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
                throw ReadError.invalidByteLengthDelimiter
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
