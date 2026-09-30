//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Output stream for writing a "varint-proto" Backup file, where headers and
/// frames are represented as concatenated, varint-prefixed serialized protos.
class BackupArchiveProtoOutputStream: BackupArchiveOutputStream {
    private let outputStream: TransformingOutputStream
    private let exportProgress: BackupArchiveExportProgress?

    /// - Important
    /// In practice, the "varint-prefixing" of serialized protos is implemented
    /// via a `ChunkedOutputStreamTransform`. Consequently, callers must include
    /// a `ChunkedOutputStreamTransform` in the passed list of transforms.
    init(
        transforms: [any StreamTransform],
        outputStream: any OutputStreamable,
        exportProgress: BackupArchiveExportProgress?,
    ) {
        owsPrecondition(transforms.contains(where: { $0 is ChunkedOutputStreamTransform }))

        self.outputStream = TransformingOutputStream(
            transforms: transforms,
            outputStream: outputStream,
        )
        self.exportProgress = exportProgress
    }

    func writeHeader(_ header: BackupProto_BackupInfo) throws {
        let bytes = failIfThrows {
            try header.serializedData()
        }

        try outputStream.write(data: bytes)
        exportProgress?.didExportFrame()
    }

    func writeFrame(_ frame: BackupProto_Frame) throws {
        let bytes = failIfThrows {
            try frame.serializedData()
        }

        try outputStream.write(data: bytes)
        exportProgress?.didExportFrame()
    }

    func closeFileStream() throws {
        exportProgress?.didCloseStream()
        try outputStream.close()
    }
}
