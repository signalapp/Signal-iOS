//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation

/// Manages the work of determining the duration of videos.
public protocol VideoDurationHelper {

    /// Returns the duration of the decrypted video file at the provided url.
    func duration(forVideoAt fileUrl: URL) async throws -> TimeInterval
}

public class VideoDurationHelperImpl: VideoDurationHelper {

    public init() {}

    public func duration(forVideoAt fileUrl: URL) async throws -> TimeInterval {
        let sourceAsset = AVURLAsset(url: fileUrl)

        /// AVURLAsset has no ability to do error checking prior to iOS 15. This extention makes it easy to
        /// get the duration with good error checking on modern iOS and hacky error checking on legacy
        /// versions. Please delete this when we drop iOS 14.
        if #available(iOS 15.0, *) {
            let duration = try await sourceAsset.load(.duration)
            return CMTimeGetSeconds(duration)
        } else {
            let duration = CMTimeGetSeconds(sourceAsset.duration)
            if duration == 0 {
                throw DurationUnavailableError()
            } else {
                return duration
            }
        }
    }

    class DurationUnavailableError: Error {}
}

#if TESTABLE_BUILD

public class VideoDurationHelperMock: VideoDurationHelper {

    public init() {}

    public var duration: TimeInterval = 0

    public func duration(forVideoAt fileUrl: URL) async throws -> TimeInterval {
        return duration
    }
}

#endif
