// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _002_YDBToGRDBMigration: Migration {
    static let identifier: String = "YDBToGRDBMigration"
    
    // TODO: Autorelease pool???.
    static func migrate(_ db: Database) throws {
        // MARK: - Contacts
        
        var contacts: Set<Legacy.Contact> = []
        var contactThreadIds: Set<String> = []
        
        Storage.read { transaction in
            // Process the Contacts
            transaction.enumerateRows(inCollection: Legacy.contactCollection) { _, object, _, _ in
                guard let contact = object as? Legacy.Contact else { return }
                contacts.insert(contact)
            }
            
            // Process the contact threads (only want to create "real" contacts in the new structure)
            transaction.enumerateKeys(inCollection: Legacy.threadCollection) { key, _ in
                guard key.starts(with: Legacy.contactThreadPrefix) else { return }
                contactThreadIds.insert(key)
            }
        }
        
        // Insert the data into GRDB
        
        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
        
        try contacts.forEach { contact in
            let isCurrentUser: Bool = (contact.sessionID == currentUserPublicKey)
            let contactThreadId: String = TSContactThread.threadID(fromContactSessionID: contact.sessionID)
            
            // Determine if this contact is a "real" contact
            if
                // TODO: Thread.shouldBeVisible???
                isCurrentUser ||
                contactThreadIds.contains(contactThreadId) ||
                contact.isApproved ||
                contact.didApproveMe ||
                contact.isBlocked ||
                contact.hasBeenBlocked {
                // Create the contact
                // TODO: Closed group admins???
                try Contact(
                    id: contact.sessionID,
                    isTrusted: (isCurrentUser || contact.isTrusted),
                    isApproved: (isCurrentUser || contact.isApproved),
                    isBlocked: (!isCurrentUser && contact.isBlocked),
                    didApproveMe: (isCurrentUser || contact.didApproveMe),
                    hasBeenBlocked: (!isCurrentUser && (contact.hasBeenBlocked || contact.isBlocked))
                ).insert(db)
            }
            
            // Create the "Profile" for the legacy contact
            try Profile(
                id: contact.sessionID,
                name: (contact.name ?? contact.sessionID),
                nickname: contact.nickname,
                profilePictureUrl: contact.profilePictureURL,
                profilePictureFileName: contact.profilePictureFileName,
                profileEncryptionKey: contact.profileEncryptionKey
            ).insert(db)
        }
    }
}
