// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public protocol NotificationsProtocol {
    func notifyUser(_ db: Database, for interaction: Interaction, in thread: SessionThread)
    func notifyUser(_ db: Database, forIncomingCall interaction: Interaction, in thread: SessionThread)
    func notifyUser(_ db: Database, forReaction reaction: Reaction, in thread: SessionThread)
    func cancelNotifications(identifiers: [String])
    func clearAllNotifications()
}

public enum Notifications {
    /// Delay notification of incoming messages when we want to group them (eg. during background polling) to avoid
    /// firing too many notifications at the same time
    public static let delayForGroupedNotifications: TimeInterval = 5
}
