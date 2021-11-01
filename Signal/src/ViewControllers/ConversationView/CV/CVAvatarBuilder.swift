//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
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
                    return OWSProfileManager.shared.localUserProfile()
                } else {
                    return AnyUserProfileFinder().userProfile(for: address, transaction: transaction)
                }
            }()

            let badge = userProfile?.primaryBadge?.fetchBadgeContent(transaction: transaction)
            let badgeAssets = badge?.assets

            switch ConversationAvatarView.Configuration.SizeClass(avatarDiameter: diameterPoints) {
            case .tiny, .small:
                badgeImage =  Theme.isDarkThemeEnabled ? badgeAssets?.dark16 : badgeAssets?.light16
            case .medium:
                badgeImage =  Theme.isDarkThemeEnabled ? badgeAssets?.dark24 : badgeAssets?.light24
            case .large, .xlarge:
                badgeImage = Theme.isDarkThemeEnabled ? badgeAssets?.dark36 : badgeAssets?.light36
            case .custom:
                // We never vend badges if it's not one of the blessed sizes
                owsFailDebug("")
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
