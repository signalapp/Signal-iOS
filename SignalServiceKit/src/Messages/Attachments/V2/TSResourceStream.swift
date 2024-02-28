//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum TSResourceContentType {
    /// Some arbitrary file. Used when no other case applies.
    case file

    // TODO: all these associated values will be non-optional after the transition to v2.
    case image(pixelSize: CGSize?)
    case video(duration: TimeInterval?)
    case animatedImage(pixelSize: CGSize?)
    case audio(duration: TimeInterval?)

    public var isImage: Bool {
        switch self {
        case .image:
            return true
        default:
            return false
        }
    }

    public var isVideo: Bool {
        switch self {
        case .video:
            return true
        default:
            return false
        }
    }

    public var isAnimatedImage: Bool {
        switch self {
        case .animatedImage:
            return true
        default:
            return false
        }
    }

    public var isAudio: Bool {
        switch self {
        case .audio:
            return true
        default:
            return false
        }
    }
}

/// A TSResource for which we have the fullsize data on local disk.
public protocol TSResourceStream: TSResource {

    func fileURLForDeletion() throws -> URL

    func decryptedImage() async throws -> UIImage

    var concreteStreamType: ConcreteTSResourceStream { get }

    // MARK: - Cached media properties

    /// The validated content type from the content itself, not just the one declared by the
    /// mimeType (which comes from the sender and therefore can be spoofed).
    ///
    /// Only returns a value if we have it cached; will not compute a value on the fly.
    /// V2 attachments will always have a cached value.
    var cachedContentType: TSResourceContentType? { get }

    /// The validated content type from the content itself, not just the one declared by the
    /// mimeType (which comes from the sender and therefore can be spoofed).
    ///
    /// Potentially performs an expensive validation by reading the contents from disk, or uses the
    /// cached value if available.
    /// V2 attachments will always have a cached value.
    func computeContentType() -> TSResourceContentType
}
