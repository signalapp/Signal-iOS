//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Simple wrapper around an OutputStream that allows passing data through an
/// array of `StreamTransform` objects to alter the data before being written
/// out to the final destination.
public final class TransformingOutputStream: OutputStreamable {

    private let transforms: [any StreamTransform]
    private let outputStream: OutputStreamable
    private let runLoop: RunLoop?

    public init(
        transforms: [any StreamTransform],
        outputStream: OutputStreamable,
        runLoop: RunLoop? = nil
    ) {
        self.transforms = transforms
        self.outputStream = outputStream
        self.runLoop = runLoop
    }

    public func write(data: Data) throws {
        let data = try transforms.reduce(data) { try $1.transform(data: $0) }
        if data.count > 0 {
            try outputStream.write(data: data)
        }
    }

    /// Iterates through each transform, allowing it to finalize the output and write any one-time
    /// footers required by the internal transform implementation.
    public func finalizeAndWriteFooter() throws {
        while hasPendingBytes {
            let footerData = try transforms.readNextRemainingBytes()
            if footerData.count > 0 {
                try outputStream.write(data: footerData)
            }
        }
    }

    /// Checks the list of transforms and returns if any data may be available from any in the list,
    /// including buffered data or pending footer date.
    /// Once hasPendingBytes returns `false`, the stream should be considered closed
    /// and should no longer be used.
    public var hasPendingBytes: Bool {
        return
            transforms.contains { $0.hasPendingBytes }
            || transforms.compactMap { $0 as? FinalizableStreamTransform }.contains { !$0.hasFinalized }
    }

    public func close() throws {
        try finalizeAndWriteFooter()

        if let runLoop {
            outputStream.remove(from: runLoop, forMode: .default)
        }
        try outputStream.close()
    }

    // MARK: - OutputStreamable passthrough

    public func remove(from runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        self.outputStream.remove(from: runLoop, forMode: mode)
    }

    public func schedule(in runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        self.outputStream.schedule(in: runLoop, forMode: mode)
    }

}
