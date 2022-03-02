import PromiseKit
import SessionSnodeKit

@objc(LKBackgroundPoller)
public final class BackgroundPoller: NSObject {
    private static var closedGroupPoller: ClosedGroupPoller!
    private static var promises: [Promise<Void>] = []

    private override init() { }

    @objc(pollWithCompletionHandler:)
    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        promises = []
            .appending(pollForMessages())
            .appending(pollForClosedGroupMessages())
            .appending(
                Set(Storage.shared.getAllOpenGroups().values.map { $0.server })
                    .map { server in
                        let poller = OpenGroupAPI.Poller(for: server)
                        poller.stop()
                        
                        return poller.poll(isBackgroundPoll: true)
                    }
            )
        
        when(resolved: promises)
            .done { _ in
                completionHandler(.newData)
            }
            .catch { error in
                SNLog("Background poll failed due to error: \(error)")
                completionHandler(.failed)
            }
    }
    
    private static func pollForMessages() -> Promise<Void> {
        let userPublicKey = getUserHexEncodedPublicKey()
        return getMessages(for: userPublicKey)
    }
    
    private static func pollForClosedGroupMessages() -> [Promise<Void>] {
        let publicKeys = Storage.shared.getUserClosedGroupPublicKeys()
        return publicKeys.map { getMessages(for: $0) }
    }
    
    private static func getMessages(for publicKey: String) -> Promise<Void> {
        return SnodeAPI.getSwarm(for: publicKey)
            .then(on: DispatchQueue.main) { swarm -> Promise<Void> in
                guard let snode = swarm.randomElement() else { throw SnodeAPI.Error.generic }
                
                return attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.main) {
                    return SnodeAPI.getRawMessages(from: snode, associatedWith: publicKey)
                        .then(on: DispatchQueue.main) { responseData -> Promise<Void> in
                            let messages = SnodeAPI.parseRawMessagesResponse(responseData, from: snode, associatedWith: publicKey)
                            let promises = messages
                                .compactMap { json -> Promise<Void>? in
                                    // Use a best attempt approach here; we don't want to fail
                                    // the entire process if one of the messages failed to parse.
                                    guard let envelope = SNProtoEnvelope.from(json), let data = try? envelope.serializedData() else {
                                        return nil
                                    }
                                    
                                    let job = MessageReceiveJob(data: data, serverHash: json["hash"] as? String, isBackgroundPoll: true)
                                    
                                    return job.execute()
                                }
                            
                            return when(fulfilled: promises) // The promise returned by MessageReceiveJob never rejects
                        }
                }
            }
    }
}
