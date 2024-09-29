//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation

extension AVAssetExportSession {
    /// Workaround for `export(to:as:)` not being back-deployed before iOS 18.
    @available(iOSApplicationExtension, obsoleted: 18.0, message: "Use export(to:as:) instead")
    @inlinable
    public func exportAsync(to url: URL, as fileType: AVFileType, isolation: isolated (any Actor)? = #isolation) async throws {
        if #available(iOSApplicationExtension 18.0, *) {
            try await export(to: url, as: fileType)
        } else {
            outputURL = url
            outputFileType = fileType
            return try await withCheckedThrowingContinuation { continuation in
                nonisolated(unsafe) let session = self
                exportAsynchronously {
                    if session.status == .cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
