//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import YYImage

/// A TSResource for which we have the fullsize data on local disk.
public protocol TSResourceStream: TSResource {

    /// Reads the type-agnostic raw data of the attachment file from disk.
    /// Throws an error if reading/decrypting the file fails.
    func decryptedRawData() throws -> Data

    /// Interprets the data on disk as a string with standard encoding (utf-8, but thats an implementation detail).
    /// Throws an error if reading/decrypting the file fails or the data is incompatible with UIImage.
    func decryptedLongText() throws -> String

    /// Interprets the data on disk as a UIImage.
    /// Throws an error if reading/decrypting the file fails or the data is incompatible with UIImage.
    func decryptedImage() throws -> UIImage

    /// Interprets the data on disk as a YYImage.
    /// Throws an error if reading/decrypting the file fails or the data is incompatible with YYImage.
    /// YYImage is typically used for animated images, but is a subclass of UIImage and supports stills too.
    func decryptedYYImage() throws -> YYImage

    /// Interprets the data on disk as an AVAsset (video or audio).
    /// Throws an error if reading/decrypting the file fails or the data is incompatible with AVAsset.
    func decryptedAVAsset() throws -> AVAsset

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

    func computeIsValidVisualMedia() -> Bool

    // MARK: - Thumbnail Generation

    func thumbnailImage(quality: AttachmentThumbnailQuality) async -> UIImage?
    func thumbnailImageSync(quality: AttachmentThumbnailQuality) -> UIImage?

    // MARK: - Audio waveform

    func audioWaveform() -> Task<AudioWaveform, Error>
    func highPriorityAudioWaveform() -> Task<AudioWaveform, Error>
}
