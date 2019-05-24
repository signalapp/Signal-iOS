
extension LokiAPI {
    
    private static let messageSender: MessageSender = SSKEnvironment.shared.messageSender
    
    /// A p2p state struct
    internal struct P2PDetails {
        var address: String
        var port: UInt32
        var isOnline: Bool
        var timerDuration: Double
        var pingTimer: WeakTimer? = nil
        
        var target: Target {
            return Target(address: address, port: port)
        }
    }
    
    internal static var ourP2PAddress: Target? = nil
    
    /// This is where we store the p2p details of our contacts
    internal static var contactP2PDetails = [String: P2PDetails]()
    
    /// Handle P2P logic when we receive a `LokiAddressMessage`
    ///
    /// - Parameters:
    ///   - pubKey: The other users pubKey
    ///   - address: The pther users p2p address
    ///   - port: The other users p2p port
    ///   - receivedThroughP2P: Wether we received the message through p2p
    @objc public static func didReceiveLokiAddressMessage(forContact pubKey: String, address: String, port: UInt32, receivedThroughP2P: Bool) {
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
            // TODO: Set contact to online and start the ping timers
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
        // TODO: Ping the contact
    }
    
    /// Set the Contact p2p details
    ///
    /// - Parameters:
    ///   - pubKey: The public key of the contact
    ///   - address: The contacts p2p address
    ///   - port: The contacts p2p port
    @objc public static func setContactP2PDetails(forContact pubKey: String, address: String, port: UInt32) {
        let details = P2PDetails(address: address, port: port, isOnline: false, timerDuration: 10, pingTimer: nil)
        contactP2PDetails[pubKey] = details
    }
    
    /// Set our local P2P address
    ///
    /// - Parameter url: The url to our local server
    @objc public static func setOurP2PAddress(url: URL) {
        guard let scheme = url.scheme, let host = url.host, let port = url.port else { return }
        let target = Target(address: "\(scheme)://\(host)", port: UInt32(port))
        ourP2PAddress = target
    }

    /// Broadcash an online message to all our friends.
    /// This shouldn't be called inside a transaction.
    @objc public static func broadcastOnlineStatus() {
        AssertIsOnMainThread()

        let friendThreads = getAllFriendThreads()
        for thread in friendThreads {
            sendOnlineBroadcastMessage(forThread: thread)
        }
    }
    
    /// Get the `LokiAddressMessage` for the given thread.
    ///
    /// - Parameter thread: The contact thread.
    /// - Returns: The `LokiAddressMessage` for that thread.
    @objc public static func onlineBroadcastMessage(forThread thread: TSThread) -> LokiAddressMessage? {
        guard let ourAddress = ourP2PAddress else {
            Logger.error("P2P Address not set")
            return nil
        }

        return LokiAddressMessage(in: thread, address: ourAddress.address, port: ourAddress.port)
    }
    
    /// Send a `Loki Address` message to the given thread
    ///
    /// - Parameter thread: The contact thread to send the message to
    @objc public static func sendOnlineBroadcastMessage(forThread thread: TSContactThread) {
        AssertIsOnMainThread()
        
        guard let message = onlineBroadcastMessage(forThread: thread) else {
            owsFailDebug("P2P Address not set")
            return
        }
        
        messageSender.sendPromise(message: message).catch { error in
            Logger.warn("Failed to send online status to \(thread.contactIdentifier())")
        }.retainUntilComplete()
    }
    
    @objc public static func sendOnlineBroadcastMessage(forThread thread: TSContactThread, transaction: YapDatabaseReadWriteTransaction) {
        guard let ourAddress = ourP2PAddress else {
            owsFailDebug("P2P Address not set")
            return
        }
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
    
}
