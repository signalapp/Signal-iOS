// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

extension MessageReceiver {
    internal static func handleMessageRequestResponse(
        _ db: Database,
        message: MessageRequestResponse,
        dependencies: Dependencies
    ) throws {
        let userPublicKey = getUserHexEncodedPublicKey(db)
        var hadBlindedContact: Bool = false
        
        // Ignore messages which were sent from the current user
        guard message.sender != userPublicKey else { return }
        guard let senderId: String = message.sender else { return }
        
        // Prep the unblinded thread
        let unblindedThread: SessionThread = try SessionThread.fetchOrCreate(db, id: senderId, variant: .contact)
        
        // Need to handle a `MessageRequestResponse` sent to a blinded thread (ie. check if the sender matches
        // the blinded ids of any threads)
        let blindedThreadIds: Set<String> = (try? SessionThread
            .select(.id)
            .filter(SessionThread.Columns.variant == SessionThread.Variant.contact)
            .filter(SessionThread.Columns.id.like("\(SessionId.Prefix.blinded.rawValue)%"))
            .asRequest(of: String.self)
            .fetchSet(db))
            .defaulting(to: [])
        let pendingBlindedIdLookups: [BlindedIdLookup] = (try? BlindedIdLookup
            .filter(blindedThreadIds.contains(BlindedIdLookup.Columns.blindedId))
            .fetchAll(db))
            .defaulting(to: [])
        
        // Loop through all blinded threads and extract any interactions relating to the user accepting
        // the message request
        try pendingBlindedIdLookups.forEach { blindedIdLookup in
            // If the sessionId matches the blindedId then this thread needs to be converted to an un-blinded thread
            guard
                dependencies.sodium.sessionId(
                    senderId,
                    matchesBlindedId: blindedIdLookup.blindedId,
                    serverPublicKey: blindedIdLookup.openGroupPublicKey,
                    genericHash: dependencies.genericHash
                )
            else { return }
            
            // Update the lookup
            _ = try blindedIdLookup
                .with(sessionId: senderId)
                .saved(db)
            
            // Flag that we had a blinded contact and add the `blindedThreadId` to an array so we can remove
            // them at the end of processing
            hadBlindedContact = true
            
            // Update all interactions to be on the new thread
            // Note: Pending `MessageSendJobs` _shouldn't_ be an issue as even if they are sent after the
            // un-blinding of a thread, the logic when handling the sent messages should automatically
            // assign them to the correct thread
            try Interaction
                .filter(Interaction.Columns.threadId == blindedIdLookup.blindedId)
                .updateAll(db, Interaction.Columns.threadId.set(to: unblindedThread.id))
            
            _ = try SessionThread
                .filter(id: blindedIdLookup.blindedId)
                .deleteAll(db)
        }
        
        // Update the `didApproveMe` state of the sender
        try updateContactApprovalStatusIfNeeded(
            db,
            senderSessionId: senderId,
            threadId: nil,
            forceConfigSync: !hadBlindedContact // Sync here if there were no blinded contacts
        )
        
        // If there were blinded contacts then we need to assume that the 'sender' is a newly create contact and hence
        // need to update it's `isApproved` state
        if hadBlindedContact {
            try updateContactApprovalStatusIfNeeded(
                db,
                senderSessionId: userPublicKey,
                threadId: unblindedThread.id,
                forceConfigSync: true
            )
        }
        
        // Notify the user of their approval (Note: This will always appear in the un-blinded thread)
        //
        // Note: We want to do this last as it'll mean the un-blinded thread gets updated and the
        // contact approval status will have been updated at this point (which will mean the
        // `isMessageRequest` will return correctly after this is saved)
        _ = try Interaction(
            serverHash: message.serverHash,
            threadId: unblindedThread.id,
            authorId: senderId,
            variant: .infoMessageRequestAccepted,
            timestampMs: (
                message.sentTimestamp.map { Int64($0) } ??
                Int64(floor(Date().timeIntervalSince1970 * 1000))
            )
        ).inserted(db)
    }
    
    internal static func updateContactApprovalStatusIfNeeded(
        _ db: Database,
        senderSessionId: String,
        threadId: String?,
        forceConfigSync: Bool
    ) throws {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        // If the sender of the message was the current user
        if senderSessionId == userPublicKey {
            // Retrieve the contact for the thread the message was sent to (excluding 'NoteToSelf'
            // threads) and if the contact isn't flagged as approved then do so
            guard
                let threadId: String = threadId,
                let thread: SessionThread = try? SessionThread.fetchOne(db, id: threadId),
                !thread.isNoteToSelf(db),
                let contact: Contact = try? thread.contact.fetchOne(db),
                !contact.isApproved
            else { return }
            
            try? contact
                .with(isApproved: true)
                .update(db)
        }
        else {
            // The message was sent to the current user so flag their 'didApproveMe' as true (can't send a message to
            // someone without approving them)
            guard
                let contact: Contact = try? Contact.fetchOne(db, id: senderSessionId),
                !contact.didApproveMe
            else { return }

            try? contact
                .with(didApproveMe: true)
                .update(db)
        }
        
        // Force a config sync to ensure all devices know the contact approval state if desired
        guard forceConfigSync else { return }
        
        try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
    }
}
