//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SDWebImage

extension SDAnimatedImage {

    public static func sdImage(
        from attachment: AttachmentStream,
    ) throws -> SDAnimatedImage {
        // YYImage has an initializer that takes a file path, but that
        // initializer loads the entire file's data into memory.
        // So we don't use any more memory at any point compared to that.
        // YYImage does take a CIImage in another initializer, which we could
        // in theory load incrementally using CGDataProvider to reduce our
        // memory footprint, but CGDataProvider doesn't make things easy for
        // file types other than png and jpeg and its unclear if it would work
        // at all for animated images.
        let data = try attachment.decryptedRawData()
        guard let image = SDAnimatedImage(data: data) else {
            throw OWSAssertionError("Unable to decode image")
        }
        return image
    }
}
