import SessionUtilitiesKit

public protocol SessionSnodeKitStorageProtocol {

    func with(_ work: @escaping (Any) -> Void)

    func getUserPublicKey() -> String?
    func getOnionRequestPaths() -> [OnionRequestAPI.Path]
    func setOnionRequestPaths(to paths: [OnionRequestAPI.Path], using transaction: Any)
    func getSnodePool() -> Set<Snode>
    func setSnodePool(to snodePool: Set<Snode>, using transaction: Any)
    func getLastSnodePoolRefreshDate() -> Date?
    func setLastSnodePoolRefreshDate(to date: Date, using transaction: Any)
    func getSwarm(for publicKey: String) -> Set<Snode>
    func setSwarm(to swarm: Set<Snode>, for publicKey: String, using transaction: Any)
    func getLastMessageHash(for snode: Snode, associatedWith publicKey: String) -> String?
    func setLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String, to lastMessageHashInfo: JSON, using transaction: Any)
    func pruneLastMessageHashInfoIfExpired(for snode: Snode, associatedWith publicKey: String, using transaction: Any)
    func getReceivedMessages(for publicKey: String) -> Set<String>
    func setReceivedMessages(to receivedMessages: Set<String>, for publicKey: String, using transaction: Any)
}
