//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit
import SignalUI

protocol ChatListSettingsButtonDelegate: AnyObject {
    func didUpdateButton(_ settingsButtonCreator: ChatListSettingsButtonState)
}

final class ChatListSettingsButtonState {
    var hasInboxChats: Bool = false
    var hasArchivedChats: Bool = false
    var hasUnreadPaymentNotification: Bool = false

    weak var delegate: ChatListSettingsButtonDelegate?

    func updateState(
        hasInboxChats: Bool? = nil,
        hasArchivedChats: Bool? = nil,
        hasUnreadPaymentNotification: Bool? = nil
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
        if didUpdate {
            delegate?.didUpdateButton(self)
        }
    }
}
