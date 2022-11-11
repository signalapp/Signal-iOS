//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

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

    // We _DO NOT_ want to use LRUCache here; we need to gather
    // all of the avatars for this load and retain them for the
    // duration of the load.
    // TODO: Badges — Key off of avatar size? Badge size? Clear on badge update
    private var cache = [String: ConversationAvatarDataSource]()

    required init(transaction: SDSAnyReadTransaction) {
        self.transaction = transaction
    }

    func buildAvatarDataSource(forAddress address: SignalServiceAddress,
                               includingBadge: Bool,
                               localUserDisplayMode: LocalUserDisplayMode,
                               diameterPoints: UInt) -> ConversationAvatarDataSource? {
        guard let serviceIdentifier = address.serviceIdentifier else {
            owsFailDebug("Invalid address.")
            return nil
        }
        let cacheKey = serviceIdentifier
        if let dataSource = cache[cacheKey] {
            return dataSource
        }
        guard let avatar = Self.avatarBuilder.avatarImage(forAddress: address,
                                                          diameterPoints: diameterPoints,
                                                          localUserDisplayMode: localUserDisplayMode,
                                                          transaction: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }

        let badgeImage: UIImage?
        if includingBadge {
            let userProfile: OWSUserProfile? = {
                if address.isLocalAddress {
                    // TODO: Badges — Expose badge info about local user profile on OWSUserProfile
                    // TODO: Badges — Unify with ConversationAvatarDataSource
                    return OWSProfileManager.shared.localUserProfile()
                } else {
                    return AnyUserProfileFinder().userProfile(for: address, transaction: transaction)
                }
            }()

            let sizeClass = ConversationAvatarView.Configuration.SizeClass(avatarDiameter: diameterPoints)
            let badge = userProfile?.primaryBadge?.fetchBadgeContent(transaction: transaction)
            if let badgeAssets = badge?.assets {
                badgeImage = sizeClass.fetchImageFromBadgeAssets(badgeAssets)
            } else {
                badgeImage = nil
            }
        } else {
            badgeImage = nil
        }

        let result = ConversationAvatarDataSource.asset(avatar: avatar, badge: badgeImage)
        cache[cacheKey] = result
        return result
    }

    func buildAvatarDataSource(forGroupThread groupThread: TSGroupThread, diameterPoints: UInt) -> ConversationAvatarDataSource? {
        let cacheKey = groupThread.uniqueId
        if let dataSource = cache[cacheKey] {
            return dataSource
        }
        guard let avatar = Self.avatarBuilder.avatarImage(forGroupThread: groupThread,
                                                          diameterPoints: diameterPoints,
                                                          transaction: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }
        let result = ConversationAvatarDataSource.asset(avatar: avatar, badge: nil)
        cache[cacheKey] = result
        return result
    }
}
