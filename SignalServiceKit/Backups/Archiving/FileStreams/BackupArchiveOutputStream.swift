//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Output stream for a Backup file, agnostic to the underlying serialization
/// of the header and frames.
///
/// - Note
/// A "Backup file" is a single "header" followed by an arbitrary number of
/// "frames".
protocol BackupArchiveOutputStream {
    /// Write a header to the stream.
    ///
    /// - Important
    /// This must be called exactly once, before any calls to `writeFrame`.
    func writeHeader(_ header: BackupProto_BackupInfo) throws

    /// Write a frame to the stream.
    func writeFrame(_ frame: BackupProto_Frame) throws

    /// Close the stream.
    func closeFileStream() throws
}
