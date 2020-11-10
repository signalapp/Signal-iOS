import PromiseKit

@objc(LKSnodeAPI)
public final class OldSnodeAPI : NSObject {

    // MARK: Sending
    @objc(sendSignalMessage:)
    public static func objc_sendSignalMessage(_ signalMessage: SignalMessage) -> AnyPromise {
        let promise = sendSignalMessage(signalMessage).mapValues2 { AnyPromise.from($0) }.map2 { Set($0) }
        return AnyPromise.from(promise)
    }

    public static func sendSignalMessage(_ signalMessage: SignalMessage) -> Promise<Set<Promise<Any>>> {
        // Convert the message to a Loki message
        guard let lokiMessage = LokiMessage.from(signalMessage: signalMessage) else { return Promise(error: SnodeAPI.Error.generic) }
        let publicKey = lokiMessage.recipientPublicKey
        let notificationCenter = NotificationCenter.default
        notificationCenter.post(name: .calculatingPoW, object: NSNumber(value: signalMessage.timestamp))
        // Calculate proof of work
        return lokiMessage.calculatePoW().then2 { lokiMessageWithPoW -> Promise<Set<Promise<Any>>> in
            notificationCenter.post(name: .routing, object: NSNumber(value: signalMessage.timestamp))
            // Get the target snodes
            return SnodeAPI.getTargetSnodes(for: publicKey).map2 { snodes in
                notificationCenter.post(name: .messageSending, object: NSNumber(value: signalMessage.timestamp))
                let parameters = lokiMessageWithPoW.toJSON()
                return Set(snodes.map { snode in
                    // Send the message to the target snode
                    return attempt(maxRetryCount: 4, recoveringOn: SnodeAPI.workQueue) {
                        SnodeAPI.invoke(.sendMessage, on: snode, associatedWith: publicKey, parameters: parameters)
                    }.map2 { rawResponse in
                        if let json = rawResponse as? JSON, let powDifficulty = json["difficulty"] as? Int {
                            guard powDifficulty != SnodeAPI.powDifficulty, powDifficulty < 100 else { return rawResponse }
                            print("[Loki] Setting proof of work difficulty to \(powDifficulty).")
                            SnodeAPI.powDifficulty = UInt(powDifficulty)
                        } else {
                            print("[Loki] Failed to update proof of work difficulty from: \(rawResponse).")
                        }
                        return rawResponse
                    }
                })
            }
        }
    }
}
