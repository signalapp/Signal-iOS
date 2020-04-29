
@objc(LKMentionsManager)
public final class MentionsManager : NSObject {

    private static var _userHexEncodedPublicKeyCache: [String:Set<String>] = [:]
    /// A mapping from thread ID to set of user hex encoded public keys.
    @objc public static var userHexEncodedPublicKeyCache: [String:Set<String>] {
        get { LokiAPI.stateQueue.sync { _userHexEncodedPublicKeyCache } }
        set { LokiAPI.stateQueue.sync { _userHexEncodedPublicKeyCache = newValue } }
    }

    // TODO: I don't think stateQueue actually helps avoid race conditions

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: Settings
    private static var userIDScanLimit: UInt = 4096

    // MARK: Initialization
    private override init() { }

    // MARK: Implementation
    @objc public static func cache(_ hexEncodedPublicKey: String, for threadID: String) {
        if let cache = userHexEncodedPublicKeyCache[threadID] {
            userHexEncodedPublicKeyCache[threadID] = cache.union([ hexEncodedPublicKey ])
        } else {
            userHexEncodedPublicKeyCache[threadID] = [ hexEncodedPublicKey ]
        }
    }

    @objc public static func getMentionCandidates(for query: String, in threadID: String) -> [Mention] {
        // Prepare
        guard let cache = userHexEncodedPublicKeyCache[threadID] else { return [] }
        var candidates: [Mention] = []
        // Gather candidates
        var publicChat: LokiPublicChat?
        storage.dbReadConnection.read { transaction in
            publicChat = LokiDatabaseUtilities.getPublicChat(for: threadID, in: transaction)
        }
        storage.dbReadConnection.read { transaction in
            candidates = cache.flatMap { hexEncodedPublicKey in
                let uncheckedDisplayName: String?
                if let publicChat = publicChat {
                    uncheckedDisplayName = UserDisplayNameUtilities.getPublicChatDisplayName(for: hexEncodedPublicKey, in: publicChat.channel, on: publicChat.server)
                } else {
                    uncheckedDisplayName = UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey)
                }
                guard let displayName = uncheckedDisplayName else { return nil }
                guard !displayName.hasPrefix("Anonymous") else { return nil }
                return Mention(hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName)
            }
        }
        candidates = candidates.filter { $0.hexEncodedPublicKey != getUserHexEncodedPublicKey() }
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

    @objc public static func populateUserHexEncodedPublicKeyCacheIfNeeded(for threadID: String, in transaction: YapDatabaseReadTransaction? = nil) {
        guard userHexEncodedPublicKeyCache[threadID] == nil else { return }
        var result: Set<String> = []
        func populate(in transaction: YapDatabaseReadTransaction) {
            guard let thread = TSThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
            let interactions = transaction.ext(TSMessageDatabaseViewExtensionName) as! YapDatabaseViewTransaction
            interactions.enumerateKeysAndObjects(inGroup: threadID) { _, _, object, index, _ in
                guard let message = object as? TSIncomingMessage, index < userIDScanLimit else { return }
                result.insert(message.authorId)
            }
        }
        if let transaction = transaction {
            populate(in: transaction)
        } else {
            storage.dbReadConnection.read { transaction in
                populate(in: transaction)
            }
        }
        result.insert(getUserHexEncodedPublicKey())
        userHexEncodedPublicKeyCache[threadID] = result
    }
}
