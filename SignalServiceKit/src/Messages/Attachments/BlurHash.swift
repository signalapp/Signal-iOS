//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class BlurHash: NSObject {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    // This should be generous.
    private static let maxLength = 100

    // A custom base 83 encoding is used.
    //
    // See: https://github.com/woltapp/blurhash/blob/master/Algorithm.md
    private static let validCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    @objc
    public class func isValidBlurHash(_ blurHash: String?) -> Bool {
        guard let blurHash = blurHash else {
            return false
        }
        guard blurHash.count > 0 && blurHash.count < maxLength else {
            return false
        }
        return blurHash.unicodeScalars.allSatisfy { validCharacterSet.contains($0) }
    }

    @objc(ensureBlurHashForAttachmentStream:)
    public class func ensureBlurHashObjc(for attachmentStream: TSAttachmentStream) -> AnyPromise {
        return AnyPromise(ensureBlurHash(for: attachmentStream))
    }

    public class func ensureBlurHash(for attachmentStream: TSAttachmentStream) -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()

        DispatchQueue.global().async {
            guard attachmentStream.blurHash == nil else {
                // Attachment already has a blur hash.
                resolver.fulfill(())
                return
            }
            guard attachmentStream.isValidVisualMedia else {
                // Never fail; blurHashes are strictly optional.
                resolver.fulfill(())
                return
            }
            // Use the smallest available thumbnail; quality doesn't matter.
            guard let thumbnail: UIImage = attachmentStream.thumbnailImageSmallSync() else {
                // Never fail; blurHashes are strictly optional.
                owsFailDebug("Could not load small thumbnail.")
                resolver.fulfill(())
                return
            }
            // We use 4x3 placeholders.
            guard let blurHash = thumbnail.blurHash(numberOfComponents: (4, 3)) else {
                // Never fail; blurHashes are strictly optional.
                owsFailDebug("Could not generate blurHash.")
                resolver.fulfill(())
                return
            }
            guard self.isValidBlurHash(blurHash) else {
                // Never fail; blurHashes are strictly optional.
                owsFailDebug("Generated invalid blurHash.")
                resolver.fulfill(())
                return
            }
            self.databaseStorage.write { transaction in
                attachmentStream.update(withBlurHash: blurHash, transaction: transaction)
            }
            Logger.verbose("Generated blurHash.")
            resolver.fulfill(())
        }

        return promise
    }

    @objc(imageForBlurHash:)
    public class func image(for blurHash: String) -> UIImage? {
        let thumbnailSize = imageSize(for: blurHash)
        guard let image = UIImage(blurHash: blurHash, size: thumbnailSize) else {
            owsFailDebug("Couldn't generate image for blurHash.")
            return nil
        }
        return image
    }

    private class func imageSize(for blurHash: String) -> CGSize {
        guard let size = BlurHashDecode.contentSize(for: blurHash) else {
            // A small thumbnail size will suffice.
            //
            // We use a slightly smaller size than we need to
            // to future-proof this in case we decide to improve
            // the quality in a future release.
            let defaultSize: CGFloat = 16
            return CGSize(width: defaultSize, height: defaultSize)
        }
        return size
    }
}
