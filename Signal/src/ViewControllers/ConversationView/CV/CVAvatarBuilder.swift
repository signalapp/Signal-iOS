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
                     diameterPoints: UInt) -> UIImage? {
        guard let serviceIdentifier = address.serviceIdentifier else {
            owsFailDebug("Invalid address.")
            return nil
        }
        let cacheKey = serviceIdentifier
        if let avatar = cache[cacheKey] {
            return avatar
        }
        guard let avatar = Self.avatarBuilder.avatarImage(forAddress: address,
                                                          diameterPoints: diameterPoints,
                                                          localUserDisplayMode: localUserDisplayMode,
                                                          transaction: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }
        cache[cacheKey] = avatar
        return avatar
    }

    func buildAvatar(forGroupThread groupThread: TSGroupThread, diameterPoints: UInt) -> UIImage? {
        let cacheKey = groupThread.uniqueId
        if let avatar = cache[cacheKey] {
            return avatar
        }
        guard let avatar = Self.avatarBuilder.avatarImage(forGroupThread: groupThread,
                                                          diameterPoints: diameterPoints,
                                                          transaction: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }
        cache[cacheKey] = avatar
        return avatar
    }
}
