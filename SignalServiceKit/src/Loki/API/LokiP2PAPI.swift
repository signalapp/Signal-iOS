
// TODO: Match Android design

@objc(LKP2PAPI)
public class LokiP2PAPI : NSObject {
    private static let storage = OWSPrimaryStorage.shared()
    private static let messageSender = SSKEnvironment.shared.messageSender
    private static let messageReceiver = SSKEnvironment.shared.messageReceiver
    private static let ourHexEncodedPubKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    /// The amount of time before pinging when a user is set to offline
    private static let offlinePingTime = 2 * kMinuteInterval

    /// A p2p state struct
    public struct PeerInfo {
        public var address: String
        public var port: UInt16
        public var isOnline: Bool
        public var timerDuration: Double
        public var pingTimer: Timer? = nil
    }
    
    /// Our p2p address
    private static var ourP2PAddress: LokiAPITarget? = nil
    
    /// This is where we store the p2p details of our contacts
    private static var peerInfo = [String:PeerInfo]()
    
    // MARK: - Public functions
    
    /// Set our local P2P address
    ///
    /// - Parameter url: The url to our local server
    @objc public static func setOurP2PAddress(url: URL) {
        guard let scheme = url.scheme, let host = url.host, let port = url.port else { return }
        let target = LokiAPITarget(address: "\(scheme)://\(host)", port: UInt16(port))
        ourP2PAddress = target
    }
    
    /// Ping a contact
    ///
    /// - Parameter pubKey: The contact hex pubkey
    @objc(pingContact:)
    public static func ping(contact pubKey: String) {
        // Dispatch on the main queue so we escape any transaction blocks
        DispatchQueue.main.async {
            var contactThread: TSThread? = nil
            storage.dbReadConnection.read { transaction in
                contactThread = TSContactThread.getWithContactId(pubKey, transaction: transaction)
            }
            
            guard let thread = contactThread else {
                print("[Loki] Failed to fetch thread when attempting to ping: \(pubKey).")
                return
            }

            guard let message = createLokiAddressMessage(for: thread, isPing: true) else {
                print("[Loki] Failed to build ping message for: \(pubKey).")
                return
            }
            
            messageSender.sendPromise(message: message).retainUntilComplete()
        }
    }

    /// Broadcast an online message to all our friends.
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
    
    public static func handleReceivedMessage(base64EncodedData: String) {
        guard let data = Data(base64Encoded: base64EncodedData) else {
            print("[Loki] Failed to decode data for P2P message.")
            return
        }
        guard let envelope = try? LokiMessageWrapper.unwrap(data: data) else {
            print("[Loki] Failed to unwrap data for P2P message.")
            return
        }
        // We need to set the P2P field on the envelope
        let builder = envelope.asBuilder()
        builder.setIsPtpMessage(true)
        // Send it to the message receiver
        do {
            let newEnvelope = try builder.build()
            let envelopeData = try newEnvelope.serializedData()
            messageReceiver.handleReceivedEnvelopeData(envelopeData)
        } catch let error {
            print("[Loki] Something went wrong during proto conversion: \(error).")
        }
    }
    
    // MARK: - Internal functions
    
    /// Get the P2P details for the given contact.
    ///
    /// - Parameter pubKey: The contact hex pubkey
    /// - Returns: The P2P Details or nil if they don't exist
    public static func getInfo(for hexEncodedPublicKey: String) -> PeerInfo? {
        return peerInfo[hexEncodedPublicKey]
    }
    
    /// Get the `LokiAddressMessage` for the given thread.
    ///
    /// - Parameter thread: The contact thread.
    /// - Returns: The `LokiAddressMessage` for that thread.
    @objc public static func onlineBroadcastMessage(forThread thread: TSThread) -> LokiAddressMessage? {
        return createLokiAddressMessage(for: thread, isPing: false)
    }
    
    /// Handle P2P logic when we receive a `LokiAddressMessage`
    ///
    /// - Parameters:
    ///   - pubKey: The other users pubKey
    ///   - address: The pther users p2p address
    ///   - port: The other users p2p port
    ///   - receivedThroughP2P: Wether we received the message through p2p
    @objc internal static func didReceiveLokiAddressMessage(forContact pubKey: String, address: String, port: UInt16, receivedThroughP2P: Bool) {
        // Stagger the ping timers so that contacts don't ping each other at the same time
        let timerDuration = pubKey < ourHexEncodedPubKey ? 1 * kMinuteInterval : 2 * kMinuteInterval
        
        // Get out current contact details
        let oldContactInfo = peerInfo[pubKey]
        
        // Set the new contact details
        // A contact is always assumed to be offline unless the specific conditions below are met
        let info = PeerInfo(address: address, port: port, isOnline: false, timerDuration: timerDuration, pingTimer: nil)
        peerInfo[pubKey] = info
        
        // Set up our checks
        let oldContactExists = oldContactInfo != nil
        let wasOnline = oldContactInfo?.isOnline ?? false
        let isPeerInfoMatching = oldContactInfo?.address == address && oldContactInfo?.port == port
        
        /*
         We need to check if we should ping the user.
         We don't ping the user IF:
         - We had old contact details
         - We got a P2P message
         - The old contact was set as `Online`
         - The new p2p details match the old one
         */
        if oldContactExists && receivedThroughP2P && wasOnline && isPeerInfoMatching {
            setOnline(true, forContact: pubKey)
            return
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
    
    internal static func markOnline(_ hexEncodedPublicKey: String) {
        setOnline(true, forContact: hexEncodedPublicKey)
    }
    
    internal static func markOffline(_ hexEncodedPublicKey: String) {
        setOnline(false, forContact: hexEncodedPublicKey)
    }
    
    /// Mark a contact as online or offline.
    ///
    /// - Parameters:
    ///   - isOnline: Whether to set the contact to online or offline.
    ///   - pubKey: The contact hex pubKey
    @objc internal static func setOnline(_ isOnline: Bool, forContact pubKey: String) {
        // Make sure we are on the main thread
        DispatchQueue.main.async {
            guard var info = peerInfo[pubKey] else { return }
            
            let interval = isOnline ? info.timerDuration : offlinePingTime
            
            // Setup a new timer
            info.pingTimer?.invalidate()
            info.pingTimer = WeakTimer.scheduledTimer(timeInterval: interval, target: self, userInfo: nil, repeats: true) { _ in ping(contact: pubKey) }
            info.isOnline = isOnline
            
            peerInfo[pubKey] = info
            
            NotificationCenter.default.post(name: .contactOnlineStatusChanged, object: pubKey)
        }
    }
    
    // MARK: - Private functions
    
    private static func sendOnlineBroadcastMessage(forThread thread: TSContactThread) {
        AssertIsOnMainThread()
        
        guard let message = onlineBroadcastMessage(forThread: thread) else {
            print("[Loki] P2P address not set.")
            return
        }
        
        messageSender.sendPromise(message: message).catch { error in
            Logger.warn("Failed to send online status to \(thread.contactIdentifier()).")
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
    
    private static func createLokiAddressMessage(for thread: TSThread, isPing: Bool) -> LokiAddressMessage? {
        guard let ourAddress = ourP2PAddress else {
            print("[Loki] P2P address not set.")
            return nil
        }
        
        return LokiAddressMessage(in: thread, address: ourAddress.address, port: ourAddress.port, isPing: isPing)
    }
}
