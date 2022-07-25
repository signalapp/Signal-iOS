// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

extension MessageReceiver {
    internal static func handleTypingIndicator(_ db: Database, message: TypingIndicator) throws {
        guard
            let senderPublicKey: String = message.sender,
            let thread: SessionThread = try SessionThread.fetchOne(db, id: senderPublicKey)
        else { return }
        
        switch message.kind {
            case .started:
                TypingIndicators.didStartTyping(
                    db,
                    threadId: thread.id,
                    threadVariant: thread.variant,
                    threadIsMessageRequest: thread.isMessageRequest(db),
                    direction: .incoming,
                    timestampMs: message.sentTimestamp.map { Int64($0) }
                )
                
            case .stopped:
                TypingIndicators.didStopTyping(db, threadId: thread.id, direction: .incoming)
            
            default:
                SNLog("Unknown TypingIndicator Kind ignored")
                return
        }
    }
}
