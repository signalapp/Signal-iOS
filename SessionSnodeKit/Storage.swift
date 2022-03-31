import SessionUtilitiesKit
import PromiseKit
import Sodium

public protocol SessionSnodeKitStorageProtocol {

    @discardableResult
    func write(with block: @escaping (Any) -> Void) -> Promise<Void>
    @discardableResult
    func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void>
    func writeSync(with block: @escaping (Any) -> Void)

    func getUserPublicKey() -> String?
    func getUserED25519KeyPair() -> Box.KeyPair?
    func getOnionRequestPaths() -> [OnionRequestAPI.Path]
    func setOnionRequestPaths(to paths: [OnionRequestAPI.Path], using transaction: Any)
    func getSnodePool() -> Set<Legacy.Snode>
    func setSnodePool(to snodePool: Set<Legacy.Snode>, using transaction: Any)
    func getLastSnodePoolRefreshDate() -> Date?
    func setLastSnodePoolRefreshDate(to date: Date, using transaction: Any)
    func getSwarm(for publicKey: String) -> Set<Legacy.Snode>
    func setSwarm(to swarm: Set<Legacy.Snode>, for publicKey: String, using transaction: Any)
    func getLastMessageHash(for snode: Legacy.Snode, associatedWith publicKey: String) -> String?
    func setLastMessageHashInfo(for snode: Legacy.Snode, associatedWith publicKey: String, to lastMessageHashInfo: JSON, using transaction: Any)
    func pruneLastMessageHashInfoIfExpired(for snode: Legacy.Snode, associatedWith publicKey: String)
    func getReceivedMessages(for publicKey: String) -> Set<String>
    func setReceivedMessages(to receivedMessages: Set<String>, for publicKey: String, using transaction: Any)
}
