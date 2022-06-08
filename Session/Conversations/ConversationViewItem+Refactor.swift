// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionSnodeKit
import SessionMessagingKit

extension ConversationViewItem {
    func deleteLocallyAction() {
        guard let message: TSMessage = self.interaction as? TSMessage else { return }
        
        Storage.write { transaction in
            MessageInvalidator.invalidate(message, with: transaction)
            message.remove(with: transaction)
            
            if message.interactionType() == .outgoingMessage {
                Storage.shared.cancelPendingMessageSendJobIfNeeded(for: message.timestamp, using: transaction)
            }
        }
    }

    func deleteRemotelyAction() {
        guard let message: TSMessage = self.interaction as? TSMessage else { return }
        
        if isGroupThread {
            guard let groupThread: TSGroupThread = message.thread as? TSGroupThread else { return }
            
            // Only allow deletion on incoming and outgoing messages
            guard message.interactionType() == .incomingMessage || message.interactionType() == .outgoingMessage else {
                return
            }
            
            if groupThread.isOpenGroup {
                // Make sure it's an open group message and get the open group
                guard message.isOpenGroupMessage, let uniqueId: String = groupThread.uniqueId, let openGroup: OpenGroup = Storage.shared.getOpenGroup(for: uniqueId) else {
                    return
                }

                // If it's an incoming message the user must have moderator status
                if message.interactionType() == .incomingMessage {
                    guard let userPublicKey: String = Storage.shared.getUserPublicKey() else { return }
                    
                    if !OpenGroupManager.isUserModeratorOrAdmin(userPublicKey, for: openGroup.room, on: openGroup.server) {
                        return
                    }
                }
                
                // Delete the message
                OpenGroupAPI.messageDelete(message.openGroupServerMessageID, in: openGroup.room, on: openGroup.server)
                    .catch { _ in
                        // Roll back
                        message.save()
                    }
                    .retainUntilComplete()
            }
            else {
                guard let serverHash: String = message.serverHash else { return }
                
                let groupPublicKey: String = LKGroupUtilities.getDecodedGroupID(groupThread.groupModel.groupId)
                
                SnodeAPI.deleteMessage(publicKey: groupPublicKey, serverHashes: [serverHash])
                    .catch { _ in
                        // Roll back
                        message.save()
                    }
                    .retainUntilComplete()
            }
        }
        else {
            guard let contactThread: TSContactThread = message.thread as? TSContactThread, let serverHash: String = message.serverHash else {
                return
            }
            
            SnodeAPI.deleteMessage(publicKey: contactThread.contactSessionID(), serverHashes: [serverHash])
                .catch { _ in
                    // Roll back
                    message.save()
                }
                .retainUntilComplete()
        }
    }

    // Remove this after the unsend request is enabled
    func deleteAction() {
        Storage.write { transaction in
            self.interaction.remove(with: transaction)
            
            if self.interaction.interactionType() == .outgoingMessage {
                Storage.shared.cancelPendingMessageSendJobIfNeeded(for: self.interaction.timestamp, using: transaction)
            }
        }
        
        
        if self.isGroupThread {
            guard let message: TSMessage = self.interaction as? TSMessage, let groupThread: TSGroupThread = message.thread as? TSGroupThread else {
                return
            }
            
            // Only allow deletion on incoming and outgoing messages
            guard message.interactionType() == .incomingMessage || message.interactionType() == .outgoingMessage else {
                return
            }
            
            // Make sure it's an open group message and get the open group
            guard message.isOpenGroupMessage, let uniqueId: String = groupThread.uniqueId, let openGroup: OpenGroup = Storage.shared.getOpenGroup(for: uniqueId) else {
                return
            }
            
            // If it's an incoming message the user must have moderator status
            if message.interactionType() == .incomingMessage {
                guard let userPublicKey: String = Storage.shared.getUserPublicKey() else { return }
                
                if !OpenGroupManager.isUserModeratorOrAdmin(userPublicKey, for: openGroup.room, on: openGroup.server) {
                    return
                }
            }
            
            // Delete the message
            OpenGroupAPI.messageDelete(message.openGroupServerMessageID, in: openGroup.room, on: openGroup.server)
                .catch { _ in
                    // Roll back
                    message.save()
                }
                .retainUntilComplete()
        }
    }
}
