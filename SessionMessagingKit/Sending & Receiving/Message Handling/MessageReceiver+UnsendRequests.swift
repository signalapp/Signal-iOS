// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionSnodeKit
import SessionUtilitiesKit

extension MessageReceiver {
    public static func handleUnsendRequest(_ db: Database, message: UnsendRequest) throws {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        guard message.sender == message.author || userPublicKey == message.sender else { return }
        guard let author: String = message.author, let timestampMs: UInt64 = message.timestamp else { return }
        
        let maybeInteraction: Interaction? = try Interaction
            .filter(Interaction.Columns.timestampMs == Int64(timestampMs))
            .filter(Interaction.Columns.authorId == author)
            .fetchOne(db)
        
        guard
            let interactionId: Int64 = maybeInteraction?.id,
            let interaction: Interaction = maybeInteraction
        else { return }
        
        // Mark incoming messages as read and remove any of their notifications
        if interaction.variant == .standardIncoming {
            try Interaction.markAsRead(
                db,
                interactionId: interactionId,
                threadId: interaction.threadId,
                includingOlder: false,
                trySendReadReceipt: false
            )
            
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: interaction.notificationIdentifiers)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: interaction.notificationIdentifiers)
        }
        
        if author == message.sender, let serverHash: String = interaction.serverHash {
            SnodeAPI.deleteMessage(publicKey: author, serverHashes: [serverHash]).retainUntilComplete()
        }
         
        switch (interaction.variant, (author == message.sender)) {
            case (.standardOutgoing, _), (_, false):
                _ = try interaction.delete(db)
                
            case (_, true):
                _ = try interaction
                    .markingAsDeleted()
                    .saved(db)
                
                _ = try interaction.attachments
                    .deleteAll(db)
                
                if let serverHash: String = interaction.serverHash {
                    try SnodeReceivedMessageInfo.handlePotentialDeletedOrInvalidHash(
                        db,
                        potentiallyInvalidHashes: [serverHash]
                    )
                }
        }
    }
}
