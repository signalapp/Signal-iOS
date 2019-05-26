
@objc public class LokiP2PManager : NSObject {
    private static let storage = OWSPrimaryStorage.shared()
    private static let messageSender: MessageSender = SSKEnvironment.shared.messageSender
    private static let ourHexEncodedPubKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    /// The amount of time before pinging when a user is set to offline
    private static let offlinePingTime = 2 * kMinuteInterval

    /// A p2p state struct
    internal struct P2PDetails {
        var address: String
        var port: UInt32
        var isOnline: Bool
        var timerDuration: Double
        var pingTimer: Timer? = nil
        
        var target: LokiAPI.Target {
            return LokiAPI.Target(address: address, port: port)
        }
    }
    
    /// Our p2p address
    private static var ourP2PAddress: LokiAPI.Target? = nil
    
    /// This is where we store the p2p details of our contacts
    private static var contactP2PDetails = [String: P2PDetails]()
    
    // MARK: - Public functions
    
    /// Set our local P2P address
    ///
    /// - Parameter url: The url to our local server
    @objc public static func setOurP2PAddress(url: URL) {
        guard let scheme = url.scheme, let host = url.host, let port = url.port else { return }
        let target = LokiAPI.Target(address: "\(scheme)://\(host)", port: UInt32(port))
        ourP2PAddress = target
    }
    
    /// Ping a contact
    ///
    /// - Parameter pubKey: The contact hex pubkey
    @objc(pingContact:)
    public static func ping(contact pubKey: String) {
        // Dispatch on the main queue so we escape any transaction blocks
        DispatchQueue.main.async {
            guard let thread = TSContactThread.fetch(uniqueId: pubKey) else {
                Logger.warn("[Loki][Ping] Failed to fetch thread for \(pubKey)")
                return
            }
            guard let message = lokiAddressMessage(for: thread, isPing: true) else {
                Logger.warn("[Loki][Ping] Failed to build ping message for \(pubKey)")
                return
            }
            
            messageSender.sendPromise(message: message).retainUntilComplete()
        }
    }

    /// Broadcash an online message to all our friends.
    /// This shouldn't be called inside a transaction.
    @objc public static func broadcastOnlineStatus() {
        // Escape any transaction blocks
        DispatchQueue.main.async {
            let friendThreads = getAllFriendThreads()
            for thread in friendThreads {
                sendOnlineBroadcastMessage(forThread: thread)
            }
        }
    }
    
    // MARK: - Internal functions
    
    /// Get the P2P details for the given contact.
    ///
    /// - Parameter pubKey: The contact hex pubkey
    /// - Returns: The P2P Details or nil if they don't exist
    internal static func getDetails(forContact pubKey: String) -> P2PDetails? {
        return contactP2PDetails[pubKey]
    }
    
    /// Get the `LokiAddressMessage` for the given thread.
    ///
    /// - Parameter thread: The contact thread.
    /// - Returns: The `LokiAddressMessage` for that thread.
    @objc public static func onlineBroadcastMessage(forThread thread: TSThread) -> LokiAddressMessage? {
        return lokiAddressMessage(for: thread, isPing: false)
    }
    
    /// Handle P2P logic when we receive a `LokiAddressMessage`
    ///
    /// - Parameters:
    ///   - pubKey: The other users pubKey
    ///   - address: The pther users p2p address
    ///   - port: The other users p2p port
    ///   - receivedThroughP2P: Wether we received the message through p2p
    @objc internal static func didReceiveLokiAddressMessage(forContact pubKey: String, address: String, port: UInt32, receivedThroughP2P: Bool) {
        // Stagger the ping timers so that contacts don't ping each other at the same time
        
        let timerDuration = pubKey < ourHexEncodedPubKey ? 1 * kMinuteInterval : 2 * kMinuteInterval
        
        // Get out current contact details
        let oldContactDetails = contactP2PDetails[pubKey]
        
        // Set the new contact details
        // A contact is always assumed to be offline unless the specific conditions below are met
        let details = P2PDetails(address: address, port: port, isOnline: false, timerDuration: timerDuration, pingTimer: nil)
        
        // Set up our checks
        let oldContactExists = oldContactDetails != nil
        let wasOnline = oldContactDetails?.isOnline ?? false
        let p2pDetailsMatch = oldContactDetails?.address == address && oldContactDetails?.port == port
        
        /*
         We need to check if we should ping the user.
         We don't ping the user IF:
         - We had old contact details
         - We got a P2P message
         - The old contact was set as `Online`
         - The new p2p details match the old one
         */
        if oldContactExists && receivedThroughP2P && wasOnline && p2pDetailsMatch {
            setOnline(true, forContact: pubKey)
            return;
        }
        
        /*
         Ping the contact.
         This happens in the following scenarios:
         1. We didn't have the contact, we need to ping them to let them know our details.
         2. wasP2PMessage = false, so we assume the contact doesn't have our details.
         3. We had the contact marked as offline, we need to make sure that we can reach their server.
         4. The other contact details have changed, we need to make sure that we can reach their new server.
         */
        ping(contact: pubKey)
    }
    
    /// Mark a contact as online or offline.
    ///
    /// - Parameters:
    ///   - isOnline: Whether to set the contact to online or offline.
    ///   - pubKey: The contact hexh pubKey
    @objc internal static func setOnline(_ isOnline: Bool, forContact pubKey: String) {
        // Make sure we are on the main thread
        DispatchQueue.main.async {
            guard var details = contactP2PDetails[pubKey] else { return }
            
            let interval = isOnline ? details.timerDuration : offlinePingTime
            
            // Setup a new timer
            details.pingTimer?.invalidate()
            details.pingTimer = WeakTimer.scheduledTimer(timeInterval: interval, target: self, userInfo: nil, repeats: true) { _ in ping(contact: pubKey) }
            details.isOnline = isOnline
            
            contactP2PDetails[pubKey] = details
        }
    }
    
    // MARK: - Private functions
    
    private static func sendOnlineBroadcastMessage(forThread thread: TSContactThread) {
        AssertIsOnMainThread()
        
        guard let message = onlineBroadcastMessage(forThread: thread) else {
            owsFailDebug("P2P Address not set")
            return
        }
        
        messageSender.sendPromise(message: message).catch { error in
            Logger.warn("Failed to send online status to \(thread.contactIdentifier())")
            }.retainUntilComplete()
    }
    
    private static func getAllFriendThreads() -> [TSContactThread] {
        var friendThreadIds = [String]()
        TSContactThread.enumerateCollectionObjects { (object, _) in
            guard let thread = object as? TSContactThread, let uniqueId = thread.uniqueId else { return }
            
            if thread.friendRequestStatus == .friends && thread.contactIdentifier() != ourHexEncodedPubKey {
                friendThreadIds.append(thread.uniqueId!)
            }
        }
        
        return friendThreadIds.compactMap { TSContactThread.fetch(uniqueId: $0) }
    }
    
    private static func lokiAddressMessage(for thread: TSThread, isPing: Bool) -> LokiAddressMessage? {
        guard let ourAddress = ourP2PAddress else {
            Logger.error("P2P Address not set")
            return nil
        }
        
        return LokiAddressMessage(in: thread, address: ourAddress.address, port: ourAddress.port, isPing: isPing)
    }
}
