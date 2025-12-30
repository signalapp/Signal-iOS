//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

protocol ChatListSettingsButtonDelegate: AnyObject {
    func didUpdateButton(_ settingsButtonCreator: ChatListSettingsButtonState)
}

final class ChatListSettingsButtonState {
    var hasInboxChats: Bool = false
    var hasArchivedChats: Bool = false
    var hasUnreadPaymentNotification: Bool = false
    var showBackupsFailedMenuItem: Bool = false
    var hasConsumedMediaTierCapacity: Bool = false
    var showBackupsFailedAvatarBadge: Bool = false
    var showBackupsFailedMenuItemBadge: Bool = false
    var showBackupsSubscriptionAlreadyRedeemedAvatarBadge: Bool = false
    var showBackupsSubscriptionAlreadyRedeemedMenuItem: Bool = false
    var showBackupsIAPNotFoundLocallyAvatarBadge: Bool = false
    var showBackupsIAPNotFoundLocallyMenuItem: Bool = false

    weak var delegate: ChatListSettingsButtonDelegate?

    func updateState(
        hasInboxChats: Bool? = nil,
        hasArchivedChats: Bool? = nil,
        hasUnreadPaymentNotification: Bool? = nil,
        hasConsumedMediaTierCapacity: Bool? = nil,
        showBackupsFailedAvatarBadge: Bool? = nil,
        showBackupsFailedMenuItemBadge: Bool? = nil,
        showBackupsFailedMenuItem: Bool? = nil,
        showBackupsSubscriptionAlreadyRedeemedAvatarBadge: Bool? = nil,
        showBackupsSubscriptionAlreadyRedeemedMenuItem: Bool? = nil,
        showBackupsIAPNotFoundLocallyAvatarBadge: Bool? = nil,
        showBackupsIAPNotFoundLocallyMenuItem: Bool? = nil,
    ) {
        var didUpdate = false
        if let hasInboxChats {
            didUpdate = didUpdate || self.hasInboxChats != hasInboxChats
            self.hasInboxChats = hasInboxChats
        }
        if let hasArchivedChats {
            didUpdate = didUpdate || self.hasArchivedChats != hasArchivedChats
            self.hasArchivedChats = hasArchivedChats
        }
        if let hasUnreadPaymentNotification {
            didUpdate = didUpdate || self.hasUnreadPaymentNotification != hasUnreadPaymentNotification
            self.hasUnreadPaymentNotification = hasUnreadPaymentNotification
        }
        if let hasConsumedMediaTierCapacity {
            didUpdate = didUpdate || self.hasConsumedMediaTierCapacity != hasConsumedMediaTierCapacity
            self.hasConsumedMediaTierCapacity = hasConsumedMediaTierCapacity
        }
        if let showBackupsFailedAvatarBadge {
            didUpdate = didUpdate || self.showBackupsFailedAvatarBadge != showBackupsFailedAvatarBadge
            self.showBackupsFailedAvatarBadge = showBackupsFailedAvatarBadge
        }
        if let showBackupsFailedMenuItemBadge {
            didUpdate = didUpdate || self.showBackupsFailedMenuItemBadge != showBackupsFailedMenuItemBadge
            self.showBackupsFailedMenuItemBadge = showBackupsFailedMenuItemBadge
        }
        if let showBackupsFailedMenuItem {
            didUpdate = didUpdate || self.showBackupsFailedMenuItem != showBackupsFailedMenuItem
            self.showBackupsFailedMenuItem = showBackupsFailedMenuItem
        }
        if let showBackupsSubscriptionAlreadyRedeemedAvatarBadge {
            didUpdate = didUpdate || self.showBackupsSubscriptionAlreadyRedeemedAvatarBadge != showBackupsSubscriptionAlreadyRedeemedAvatarBadge
            self.showBackupsSubscriptionAlreadyRedeemedAvatarBadge = showBackupsSubscriptionAlreadyRedeemedAvatarBadge
        }
        if let showBackupsSubscriptionAlreadyRedeemedMenuItem {
            didUpdate = didUpdate || self.showBackupsSubscriptionAlreadyRedeemedMenuItem != showBackupsSubscriptionAlreadyRedeemedMenuItem
            self.showBackupsSubscriptionAlreadyRedeemedMenuItem = showBackupsSubscriptionAlreadyRedeemedMenuItem
        }
        if let showBackupsIAPNotFoundLocallyAvatarBadge {
            didUpdate = didUpdate || self.showBackupsIAPNotFoundLocallyAvatarBadge != showBackupsIAPNotFoundLocallyAvatarBadge
            self.showBackupsIAPNotFoundLocallyAvatarBadge = showBackupsIAPNotFoundLocallyAvatarBadge
        }
        if let showBackupsIAPNotFoundLocallyMenuItem {
            didUpdate = didUpdate || self.showBackupsIAPNotFoundLocallyMenuItem != showBackupsIAPNotFoundLocallyMenuItem
            self.showBackupsIAPNotFoundLocallyMenuItem = showBackupsIAPNotFoundLocallyMenuItem
        }
        if didUpdate {
            delegate?.didUpdateButton(self)
        }
    }
}
