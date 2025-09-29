//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

// Caching builder used for a single CVC load.
// CVC loads often build the same avatars over and over.
//
// TODO: There should be real benefits to extracting a token that
//       describes the avatar content and caching avatars across
//       db transactions and updates.
//       It might help ensure that CVComponentState equality
//       works correctly.
final public class CVAvatarBuilder {

    private let transaction: DBReadTransaction

    // We _DO NOT_ want to use LRUCache here; we need to gather
    // all of the avatars for this load and retain them for the
    // duration of the load.
    // TODO: Badges — Key off of avatar size? Badge size? Clear on badge update
    private var cache = [String: ConversationAvatarDataSource]()

    init(transaction: DBReadTransaction) {
        self.transaction = transaction
    }

    func buildAvatarDataSource(forAddress address: SignalServiceAddress,
                               includingBadge: Bool,
                               localUserDisplayMode: LocalUserDisplayMode,
                               diameterPoints: UInt) -> ConversationAvatarDataSource? {
        let cacheKey: String
        if let serviceId = address.serviceId {
            cacheKey = serviceId.serviceIdString
        } else if let phoneNumber = address.phoneNumber {
            cacheKey = phoneNumber
        } else {
            owsFailDebug("Invalid address.")
            return nil
        }
        if let dataSource = cache[cacheKey] {
            return dataSource
        }
        guard let avatar = SSKEnvironment.shared.avatarBuilderRef.avatarImage(forAddress: address,
                                                                              diameterPoints: diameterPoints,
                                                                              localUserDisplayMode: localUserDisplayMode,
                                                                              transaction: transaction) else {
            owsFailDebug("Could build avatar image.")
            return nil
        }

        let badgeImage: UIImage?
        if includingBadge {
            // TODO: Badges — Unify with ConversationAvatarDataSource
            let userProfile = SSKEnvironment.shared.profileManagerRef.userProfile(for: address, tx: transaction)
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
        guard let avatar = SSKEnvironment.shared.avatarBuilderRef.avatarImage(forGroupThread: groupThread,
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
