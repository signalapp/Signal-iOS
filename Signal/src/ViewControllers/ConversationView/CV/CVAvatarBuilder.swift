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
                     localUserAvatarMode: LocalUserAvatarMode,
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
                                                      localUserAvatarMode: localUserAvatarMode,
                                                      transaction: transaction).build(with: transaction) else {
            owsFailDebug("Could build avatar image")
            return nil
        }
        let finalAvatar: UIImage
        if shouldBlurAvatar {
            guard let blurredAvatar = contactsManagerImpl.blurAvatar(rawAvatar) else {
                owsFailDebug("Could build blur avatar.")
                return nil
            }
            finalAvatar = blurredAvatar
        } else {
            finalAvatar = rawAvatar
        }

        cache[cacheKey] = finalAvatar
        return finalAvatar
    }

    func buildAvatar(forGroupThread groupThread: TSGroupThread, diameter: UInt) -> UIImage? {
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                         transaction: transaction)
        let cacheKey = groupThread.uniqueId
        if let avatar = cache[cacheKey] {
            return avatar
        }
        let avatarBuilder = OWSGroupAvatarBuilder(thread: groupThread, diameter: diameter)
        guard let rawAvatar = avatarBuilder.build(with: transaction) else {
            owsFailDebug("Could build avatar image")
            return nil
        }
        let finalAvatar: UIImage
        if shouldBlurAvatar {
            guard let blurredAvatar = contactsManagerImpl.blurAvatar(rawAvatar) else {
                owsFailDebug("Could build blur avatar.")
                return nil
            }
            finalAvatar = blurredAvatar
        } else {
            finalAvatar = rawAvatar
        }
        cache[cacheKey] = finalAvatar
        return finalAvatar
    }
}
