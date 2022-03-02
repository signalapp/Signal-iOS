import SessionUtilitiesKit

public enum ContactUtilities {
    private static func approvedContact(in threadObject: Any, using transaction: Any) -> Contact? {
        guard let thread: TSContactThread = threadObject as? TSContactThread else { return nil }
        guard thread.shouldBeVisible else { return nil }
        guard let contact: Contact = Storage.shared.getContact(with: thread.contactSessionID(), using: transaction) else {
            return nil
        }
        guard contact.didApproveMe else { return nil }
        
        return contact
    }

    public static func getAllContacts() -> [String] {
        // Collect all contacts
        var result: [Contact] = []
        Storage.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let contact: Contact = approvedContact(in: object, using: transaction) else { return }
                
                result.append(contact)
            }
        }
        func getDisplayName(for publicKey: String) -> String {
            return Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        }
        
        // Remove the current user
        if let index = result.firstIndex(where: { $0.sessionID == getUserHexEncodedPublicKey() }) {
            result.remove(at: index)
        }
        
        // Sort alphabetically
        return result
            .sorted(by: { lhs, rhs in
                (lhs.displayName(for: .regular) ?? lhs.sessionID) < (rhs.displayName(for: .regular) ?? rhs.sessionID)
            })
            .map { $0.sessionID }
    }
    
    public static func enumerateApprovedContactThreads(with block: @escaping (TSContactThread, Contact, UnsafeMutablePointer<ObjCBool>) -> ()) {
        Storage.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, stop in
                guard let contactThread: TSContactThread = object as? TSContactThread else { return }
                guard let contact: Contact = approvedContact(in: object, using: transaction) else { return }
                
                block(contactThread, contact, stop)
            }
        }
    }
    
    public static func mapping(for blindedId: String, serverPublicKey: String, using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()) -> BlindedIdMapping? {
        // TODO: Ensure the above case isn't going to be an issue due to legacy messages?.
        // Unfortunately the whole point of id-blinding is to make it hard to reverse-engineer a standard
        // sessionId, as a result in order to see if there is an unblinded contact for this blindedId we
        // can only really generate blinded ids for each contact and check if any match
        //
        // Due to this we have made a few optimisations to try and early-out as often as possible, first
        // we try to retrieve a direct cached mapping
        var mappingResult: BlindedIdMapping? = dependencies.storage.getBlindedIdMapping(with: blindedId)
        
        // No need to continue if we already have a result
        if let mapping: BlindedIdMapping = mappingResult { return mapping }
        
        // Then we try loop through all approved contact threads to see if one of those contacts can be blinded to match
        ContactUtilities.enumerateApprovedContactThreads { contactThread, contact, stop in
            guard dependencies.sodium.sessionId(contact.sessionID, matchesBlindedId: blindedId, serverPublicKey: serverPublicKey) else {
                return
            }
            
            // Cache the mapping
            let newMapping: BlindedIdMapping = BlindedIdMapping(blindedId: blindedId, sessionId: contact.sessionID, serverPublicKey: serverPublicKey)
            dependencies.storage.cacheBlindedIdMapping(newMapping)
            mappingResult = newMapping
            stop.pointee = true
        }
        
        // Finish if we have a result
        if let mapping: BlindedIdMapping = mappingResult { return mapping }
        
        // Lastly loop through existing id mappings (in case the user is looking at a different SOGS but once had
        // a thread with this contact in a different SOGS and had cached the mapping)
        dependencies.storage.enumerateBlindedIdMapping { mapping, stop in
            guard mapping.serverPublicKey != serverPublicKey else { return }
            guard dependencies.sodium.sessionId(mapping.sessionId, matchesBlindedId: blindedId, serverPublicKey: serverPublicKey) else {
                return
            }
            
            // Cache the new mapping
            let newMapping: BlindedIdMapping = BlindedIdMapping(blindedId: blindedId, sessionId: mapping.sessionId, serverPublicKey: serverPublicKey)
            dependencies.storage.cacheBlindedIdMapping(newMapping)
            mappingResult = newMapping
            stop.pointee = true
        }
        
        return mappingResult
    }
}
