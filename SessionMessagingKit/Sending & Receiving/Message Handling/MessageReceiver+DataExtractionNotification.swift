// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

extension MessageReceiver {
    internal static func handleDataExtractionNotification(_ db: Database, message: DataExtractionNotification) throws {
        guard
            let sender: String = message.sender,
            let messageKind: DataExtractionNotification.Kind = message.kind,
            let thread: SessionThread = try? SessionThread.fetchOne(db, id: sender),
            thread.variant == .contact
        else { return }
        
        _ = try Interaction(
            serverHash: message.serverHash,
            threadId: thread.id,
            authorId: sender,
            variant: {
                switch messageKind {
                    case .screenshot: return .infoScreenshotNotification
                    case .mediaSaved: return .infoMediaSavedNotification
                }
            }(),
            timestampMs: (
                message.sentTimestamp.map { Int64($0) } ??
                Int64(floor(Date().timeIntervalSince1970 * 1000))
            )
        ).inserted(db)
    }
}
