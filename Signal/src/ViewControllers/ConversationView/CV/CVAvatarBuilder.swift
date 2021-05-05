//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// Caching builder used for a single CVC load.
// CVC loads often build the same avatars over and over.
//
// TODO: There should be real benefits to extracting a token that
//       describes the avatar content and caching avatars across
//       db transactions and updates.
//       It might help ensure that CVComponentState equality
//       works correctly.
public class CVAvatarBuilder: Dependencies {

    private let transaction: SDSAnyReadTransaction

    private var cache = [String: UIImage]()

    required init(transaction: SDSAnyReadTransaction) {
        self.transaction = transaction
    }

    func buildAvatar(forAddress address: SignalServiceAddress,
                     localUserDisplayMode: LocalUserDisplayMode,
                     diameter: UInt) -> UIImage? {
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: address,
                                                                           transaction: transaction)
        guard let serviceIdentifier = address.serviceIdentifier else {
            owsFailDebug("Invalid address.")
            return nil
        }
        let cacheKey = serviceIdentifier + ".\(shouldBlurAvatar)"
        if let avatar = cache[cacheKey] {
            return avatar
        }
        let colorName = contactsManager.conversationColorName(for: address, transaction: transaction)
        guard let rawAvatar = OWSContactAvatarBuilder(address: address,
                                                      colorName: colorName,
                                                      diameter: diameter,
                                                      localUserDisplayMode: localUserDisplayMode,
                                                      transaction: transaction).build(with: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }
        guard let finalAvatar = Self.processAvatar(rawAvatar,
                                                   diameter: diameter,
                                                   shouldBlurAvatar: shouldBlurAvatar) else {
            owsFailDebug("Could build process avatar.")
            return nil
        }
        cache[cacheKey] = finalAvatar
        return finalAvatar
    }

    func buildAvatar(forGroupThread groupThread: TSGroupThread, diameter: UInt) -> UIImage? {
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                         transaction: transaction)
        let cacheKey = groupThread.uniqueId + ".\(shouldBlurAvatar)"
        if let avatar = cache[cacheKey] {
            return avatar
        }
        let avatarBuilder = OWSGroupAvatarBuilder(thread: groupThread, diameter: diameter)
        guard let rawAvatar = avatarBuilder.build(with: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }
        guard let finalAvatar = Self.processAvatar(rawAvatar,
                                                   diameter: diameter,
                                                   shouldBlurAvatar: shouldBlurAvatar) else {
            owsFailDebug("Could build process avatar.")
            return nil
        }
        cache[cacheKey] = finalAvatar
        return finalAvatar
    }

    private static func processAvatar(_ avatar: UIImage?,
                                      diameter diameterPoints: UInt,
                                      shouldBlurAvatar: Bool) -> UIImage? {
        guard let avatar = avatar else {
            return nil
        }
        if shouldBlurAvatar {
            // We don't need to worry about resizing to diameter if we're blurring;
            // blurring will always resize image.
            guard let blurredAvatar = contactsManagerImpl.blurAvatar(avatar) else {
                owsFailDebug("Could build blur avatar.")
                return nil
            }
            return blurredAvatar
        } else {
            let screenScale = UIScreen.main.scale
            let targetSizePixels = CGFloat(diameterPoints) * screenScale
            guard CGFloat(avatar.pixelWidth) <= targetSizePixels,
                  CGFloat(avatar.pixelHeight) <= targetSizePixels else {
                return avatar.resizedImage(toFillPixelSize: .square(targetSizePixels))
            }
            return avatar
        }
    }
}
