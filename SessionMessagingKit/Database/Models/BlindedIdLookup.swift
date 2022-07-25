// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This lookup is created when the user interacts with a blinded id
public struct BlindedIdLookup: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "blindedIdLookup" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case blindedId
        case sessionId
        case openGroupServer
        case openGroupPublicKey
    }
    
    public var id: String { blindedId }
    
    /// The blinded id for the user on this open group server
    public let blindedId: String
    
    /// The standard sessionId which can be used to generate this blindedId on this open group server
    ///
    /// **Note:** This value will be null if the user owning the blinded id hasn’t accepted the message request
    public let sessionId: String?
    
    /// The server for the Open Group server this blinded id belongs to
    public let openGroupServer: String
    
    /// The public key for the Open Group server this blinded id belongs to
    public let openGroupPublicKey: String
    
    // MARK: - Initialization
    
    public init(
        blindedId: String,
        sessionId: String? = nil,
        openGroupServer: String,
        openGroupPublicKey: String
    ) {
        self.blindedId = blindedId
        self.sessionId = sessionId
        self.openGroupServer = openGroupServer
        self.openGroupPublicKey = openGroupPublicKey
    }
}

// MARK: - Mutation

public extension BlindedIdLookup {
    func with(sessionId: String) -> BlindedIdLookup {
        return BlindedIdLookup(
            blindedId: self.blindedId,
            sessionId: sessionId,
            openGroupServer: self.openGroupServer,
            openGroupPublicKey: self.openGroupPublicKey
        )
    }
}

// MARK: - GRDB Interactions

public extension BlindedIdLookup {
    /// Unfortunately the whole point of id-blinding is to make it hard to reverse-engineer a standard sessionId, as a result in order
    /// to see if there is an unblinded contact for this blindedId we can only really generate blinded ids for each contact and check
    /// if any match
    ///
    /// If we can't find a match this method will still store a lookup, just with no standard sessionId value (this gives us a method to
    /// link back to the open group the blindedId originated from)
    static func fetchOrCreate(
        _ db: Database,
        blindedId: String,
        openGroupServer: String,
        openGroupPublicKey: String,
        isCheckingForOutbox: Bool,
        dependencies: SMKDependencies = SMKDependencies()
    ) throws -> BlindedIdLookup {
        var lookup: BlindedIdLookup = (try? BlindedIdLookup
            .fetchOne(db, id: blindedId))
            .defaulting(
                to: BlindedIdLookup(
                    blindedId: blindedId,
                    openGroupServer: openGroupServer.lowercased(),
                    openGroupPublicKey: openGroupPublicKey
                )
            )
        
        // If the lookup already has a resolved sessionId then just return it immediately
        guard lookup.sessionId == nil else { return lookup }
        
        // We now need to try to match the blinded id to an existing contact, this can only be done by looping
        // through all approved contacts and generating a blinded id for the provided open group for each to
        // see if it matches the provided blindedId
        let contactsThatApprovedMeCursor: RecordCursor<Contact> = try Contact
            .filter(Contact.Columns.didApproveMe == true)
            .fetchCursor(db)
        
        while let contact: Contact = try contactsThatApprovedMeCursor.next() {
            guard dependencies.sodium.sessionId(contact.id, matchesBlindedId: blindedId, serverPublicKey: openGroupPublicKey, genericHash: dependencies.genericHash) else {
                continue
            }
            
            // We found a match so update the lookup and leave the loop
            lookup = try lookup
                .with(sessionId: contact.id)
                .saved(db)
            
            // There is an edge-case where the contact might not have their 'isApproved' flag set to true
            // but if we have a `BlindedIdLookup` for them and are performing the lookup from the outbox
            // then that means we sent them a message request and the 'isApproved' flag should be true
            if isCheckingForOutbox && !contact.isApproved {
                try Contact
                    .filter(id: contact.id)
                    .updateAll(db, Contact.Columns.isApproved.set(to: true))
            }
            
            break
        }
        
        // Finish if we have a result
        guard lookup.sessionId == nil else { return lookup }
        
        // Lastly loop through existing id lookups (in case the user is looking at a different SOGS but once had
        // a thread with this contact in a different SOGS and had cached the lookup) - we really should never hit
        // this case since the contact approval status is sync'ed (the only situation I can think of is a config
        // message hasn't been handled correctly?)
        let blindedIdLookupCursor: RecordCursor<BlindedIdLookup> = try BlindedIdLookup
            .filter(BlindedIdLookup.Columns.sessionId != nil)
            .filter(BlindedIdLookup.Columns.openGroupServer != openGroupServer.lowercased())
            .fetchCursor(db)
        
        while let otherLookup: BlindedIdLookup = try blindedIdLookupCursor.next() {
            guard
                let sessionId: String = otherLookup.sessionId,
                dependencies.sodium.sessionId(
                    sessionId,
                    matchesBlindedId: blindedId,
                    serverPublicKey: openGroupPublicKey,
                    genericHash: dependencies.genericHash
                )
            else { continue }
            
            // We found a match so update the lookup and leave the loop
            lookup = try lookup
                .with(sessionId: sessionId)
                .saved(db)
            break
        }
        
        // Want to save the lookup even if it doesn't have a sessionId so it can be used when handling
        // MessageRequestResponse messages
        return try lookup
            .saved(db)
    }
}
