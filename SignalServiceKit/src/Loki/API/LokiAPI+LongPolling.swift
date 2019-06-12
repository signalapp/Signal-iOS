import PromiseKit

private typealias Callback = () -> Void

public extension LokiAPI {
    private static var isLongPolling = false
    private static var shouldStopPolling = false
    private static var usedSnodes = [LokiAPITarget]()
    private static var cancels = [Callback]()
    
    private static let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    /// Start long polling.
    /// This will send a notification if new messages were received
    @objc public static func startLongPollingIfNecessary() {
        guard !isLongPolling else { return }
        isLongPolling = true
        shouldStopPolling = false
        
        Logger.info("[Loki] Started long polling")
        
        longPoll()
    }
    
    /// Stop long polling
    @objc public static func stopLongPolling() {
        shouldStopPolling = true
        isLongPolling = false
        usedSnodes.removeAll()
        cancelAllPromises()
        
        Logger.info("[Loki] Stopped long polling")
    }
    
    /// The long polling loop
    private static func longPoll() {
        // This is here so we can stop the infinite loop
        guard !shouldStopPolling else { return }
        
        getSwarm(for: hexEncodedPublicKey).then { _ -> Guarantee<[Result<Void>]> in
            var promises = [Promise<Void>]()
            let connections = 3
            for i in 0..<connections {
                let (promise, cancel) = openConnection()
                promises.append(promise)
                cancels.append(cancel)
            }
            return when(resolved: promises)
        }.done { _ in
                // Since all promises are complete, we can clear the cancels
                cancelAllPromises()
                
                // Keep long polling until it is stopped
                longPoll()
        }.retainUntilComplete()
    }
    
    private static func cancelAllPromises() {
        cancels.forEach { cancel in cancel() }
        cancels.removeAll()
    }
    
    private static func getUnusedSnodes() -> [LokiAPITarget] {
        let snodes = LokiAPI.swarmCache[hexEncodedPublicKey] ?? []
        return snodes.filter { !usedSnodes.contains($0) }
    }

    /// Open a connection to an unused snode and get messages from it
    private static func openConnection() -> (Promise<Void>, cancel: Callback) {
        var isCancelled = false
        
        let cancel = {
            isCancelled = true
        }
        
        func connectToNextSnode() -> Promise<Void> {
            guard let nextSnode = getUnusedSnodes().first else {
                // We don't have anymore unused snodes
                return Promise.value(())
            }
            
            // Add the snode to the used array
            usedSnodes.append(nextSnode)
            
            func getMessagesInfinitely(from target: LokiAPITarget) -> Promise<Void> {
                // The only way to exit the infinite loop is to throw an error 3 times or cancel
                return getRawMessages(from: target, usingLongPolling: true).then { rawResponse -> Promise<Void> in
                    // Check if we need to abort
                    guard !isCancelled else { throw PMKError.cancelled }
                    
                    // Process the messages
                    let messages = parseRawMessagesResponse(rawResponse, from: target)
                    
                    // Send our messages as a notification
                    NotificationCenter.default.post(name: .newMessagesReceived, object: nil, userInfo: ["messages": messages])
                    
                    // Continue fetching if we haven't cancelled
                    return getMessagesInfinitely(from: target)
                }.retryingIfNeeded(maxRetryCount: 3)
            }
            
            // Keep getting messages for this snode
            // If we errored out then connect to the next snode
            return getMessagesInfinitely(from: nextSnode).recover { _ -> Promise<Void> in
                // Cancelled, so just return successfully
                guard !isCancelled else { return Promise.value(()) }
                
                // Connect to the next snode if we haven't cancelled
                // We also need to remove the cached snode so we don't contact it again
                dropIfNeeded(nextSnode, hexEncodedPublicKey: hexEncodedPublicKey)
                return connectToNextSnode()
            }
        }
        
        // Keep connecting to snodes
        return (connectToNextSnode(), cancel)
    }
}
