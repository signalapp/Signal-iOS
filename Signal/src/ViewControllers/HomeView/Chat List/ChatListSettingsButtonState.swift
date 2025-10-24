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
    var hasBackupError: Bool = false
    var hasConsumedMediaTierCapacity: Bool = false
    var showAvatarBackupBadge: Bool = false
    var showMenuBackupBadge: Bool = false

    weak var delegate: ChatListSettingsButtonDelegate?

    func updateState(
        hasInboxChats: Bool? = nil,
        hasArchivedChats: Bool? = nil,
        hasUnreadPaymentNotification: Bool? = nil,
        hasBackupError: Bool? = nil,
        hasConsumedMediaTierCapacity: Bool? = nil,
        showAvatarBackupBadge: Bool? = nil,
        showMenuBackupBadge: Bool? = nil,
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
        if let hasBackupError {
            didUpdate = didUpdate || self.hasBackupError != hasBackupError
            self.hasBackupError = hasBackupError
        }
        if let hasConsumedMediaTierCapacity {
            didUpdate = didUpdate || self.hasConsumedMediaTierCapacity != hasConsumedMediaTierCapacity
            self.hasConsumedMediaTierCapacity = hasConsumedMediaTierCapacity
        }
        if let showAvatarBackupBadge {
            didUpdate = didUpdate || self.showAvatarBackupBadge != showAvatarBackupBadge
            self.showAvatarBackupBadge = showAvatarBackupBadge
        }
        if let showMenuBackupBadge {
            didUpdate = didUpdate || self.showMenuBackupBadge != showMenuBackupBadge
            self.showMenuBackupBadge = showMenuBackupBadge
        }
        if didUpdate {
            delegate?.didUpdateButton(self)
        }
    }
}
