
extension LokiAPI {
    private static let messageSender: MessageSender = SSKEnvironment.shared.messageSender
    internal static var ourP2PAddress: Target? = nil
    
    /// Set our local P2P address
    ///
    /// - Parameter url: The url to our local server
    @objc public static func setOurP2PAddress(url: URL) {
        guard let port = url.port else { return }
        let target = Target(address: url.absoluteString, port: UInt32(port))
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
        }
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
