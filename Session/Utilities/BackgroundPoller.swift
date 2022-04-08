// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit
import SessionMessagingKit

@objc(LKBackgroundPoller)
public final class BackgroundPoller : NSObject {
    private static var closedGroupPoller: ClosedGroupPoller!
    private static var promises: [Promise<Void>] = []

    private override init() { }

    @objc(pollWithCompletionHandler:)
    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        promises = []
        promises.append(pollForMessages())
        promises.append(contentsOf: pollForClosedGroupMessages())
        
        let v2OpenGroupServers = Set(Storage.shared.getAllV2OpenGroups().values.map { $0.server })
        v2OpenGroupServers.forEach { server in
            let poller = OpenGroupPollerV2(for: server)
            poller.stop()
            promises.append(poller.poll(isBackgroundPoll: true))
        }
        when(resolved: promises).done { _ in
            completionHandler(.newData)
        }.catch { error in
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
        return SnodeAPI.getSwarm(for: publicKey).then(on: DispatchQueue.main) { swarm -> Promise<Void> in
            guard let snode = swarm.randomElement() else { throw SnodeAPI.Error.generic }
            return attempt(maxRetryCount: 4, recoveringOn: DispatchQueue.main) {
                return SnodeAPI.getRawMessages(from: snode, associatedWith: publicKey).then(on: DispatchQueue.main) { rawResponse -> Promise<Void> in
                    let messages: [SnodeReceivedMessage] = SnodeAPI.parseRawMessagesResponse(rawResponse, from: snode, associatedWith: publicKey)
                    let promises = messages.compactMap { message -> Promise<Void>? in
                        // Use a best attempt approach here; we don't want to fail the entire process
                        // if one of the messages failed to parse
                        guard
                            let envelope = SNProtoEnvelope.from(message),
                            let data = try? envelope.serializedData()
                        else { return nil }
                        
                        let job = MessageReceiveJob(
                            data: data,
                            serverHash: message.info.hash,
                            isBackgroundPoll: true
                        )
                        return job.execute()
                    }
                    
                    // Now that the MessageReceiveJob's have been created we can persist the received messages
                    if !messages.isEmpty {
                        GRDBStorage.shared.write { db in
                            messages.forEach { try? $0.info.save(db) }
                        }
                    }
                    
                    return when(fulfilled: promises) // The promise returned by MessageReceiveJob never rejects
                }
            }
        }
    }
}
