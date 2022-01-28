import PromiseKit

@objc(LKMentionsManager)
public final class MentionsManager : NSObject {

    /// A mapping from thread ID to set of user hex encoded public keys.
    ///
    /// - Note: Should only be accessed from the main queue to avoid race conditions.
    @objc public static var userPublicKeyCache: [String:Set<String>] = [:]

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: Settings
    private static var userIDScanLimit: UInt = 512

    // MARK: Initialization
    private override init() { }

    // MARK: Implementation
    @objc public static func cache(_ publicKey: String, for threadID: String) {
        if let cache = userPublicKeyCache[threadID] {
            userPublicKeyCache[threadID] = cache.union([ publicKey ])
        } else {
            userPublicKeyCache[threadID] = [ publicKey ]
        }
    }

    @objc public static func getMentionCandidates(for query: String, in threadID: String) -> [Mention] {
        // Prepare
        guard let cache = userPublicKeyCache[threadID] else { return [] }
        var candidates: [Mention] = []
        // Gather candidates
        let openGroupV2 = Storage.shared.getV2OpenGroup(for: threadID)
        storage.dbReadConnection.read { transaction in
            candidates = cache.compactMap { publicKey in
                let context: Contact.Context = (openGroupV2 != nil) ? .openGroup : .regular
                let displayNameOrNil = Storage.shared.getContact(with: publicKey)?.displayName(for: context)
                guard let displayName = displayNameOrNil else { return nil }
                guard !displayName.hasPrefix("Anonymous") else { return nil }
                return Mention(publicKey: publicKey, displayName: displayName)
            }
        }
        candidates = candidates.filter { $0.publicKey != getUserHexEncodedPublicKey() }
        // Sort alphabetically first
        candidates.sort { $0.displayName < $1.displayName }
        if query.count >= 2 {
            // Filter out any non-matching candidates
            candidates = candidates.filter { $0.displayName.lowercased().contains(query.lowercased()) }
            // Sort based on where in the candidate the query occurs
            candidates.sort {
                $0.displayName.lowercased().range(of: query.lowercased())!.lowerBound < $1.displayName.lowercased().range(of: query.lowercased())!.lowerBound
            }
        }
        // Return
        return candidates
    }

    @objc public static func populateUserPublicKeyCacheIfNeeded(for threadID: String, in transaction: YapDatabaseReadTransaction? = nil) {
        var result: Set<String> = []
        func populate(in transaction: YapDatabaseReadTransaction) {
            guard let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
            if let groupThread = thread as? TSGroupThread, groupThread.groupModel.groupType == .closedGroup {
                result = result.union(groupThread.groupModel.groupMemberIds).subtracting([ getUserHexEncodedPublicKey() ])
            } else {
                let hasOnlyCurrentUser: Bool = (
                    userPublicKeyCache[threadID]?.count == 1 &&
                    userPublicKeyCache[threadID]?.first == getUserHexEncodedPublicKey()
                )
                
                guard userPublicKeyCache[threadID] == nil || ((thread as? TSGroupThread)?.groupModel.groupType == .openGroup && hasOnlyCurrentUser) else {
                    return
                }
                
                let interactions = transaction.ext(TSMessageDatabaseViewExtensionName) as! YapDatabaseViewTransaction
                interactions.enumerateKeysAndObjects(inGroup: threadID) { _, _, object, index, _ in
                    guard let message = object as? TSIncomingMessage, index < userIDScanLimit else { return }
                    result.insert(message.authorId)
                }
            }
            result.insert(getUserHexEncodedPublicKey())
        }
        if let transaction = transaction {
            populate(in: transaction)
        } else {
            storage.dbReadConnection.read { transaction in
                populate(in: transaction)
            }
        }
        if !result.isEmpty {
            userPublicKeyCache[threadID] = result
        }
    }
}
